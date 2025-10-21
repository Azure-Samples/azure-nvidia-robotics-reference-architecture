"""Azure authentication utilities for Isaac Lab training integration.

This module provides secure authentication helpers for Azure services with private VNet support
using MSAL/DefaultAzureCredential patterns.
"""

import logging
import os
from typing import List, Optional, Union

from azure.identity import (
    DefaultAzureCredential,
    ManagedIdentityCredential,
    ClientSecretCredential,
    WorkloadIdentityCredential,
)
from azure.storage.blob import BlobServiceClient

try:
    from azure.ai.ml import MLClient
except ImportError:
    # Handle case where azure-ai-ml is not installed
    MLClient = None

logger = logging.getLogger(__name__)


class AzureAuthenticator:
    """Handles Azure authentication with fallback mechanisms.

    Prioritizes workload identity (ManagedIdentityCredential with AZURE_CLIENT_ID)
    for Kubernetes environments, with fallback to service principal.
    """

    def __init__(self):
        """Initialize authenticator with credential chain."""
        self._credential = None
        self._tenant_id = os.getenv("AZURE_TENANT_ID")
        self._client_id = os.getenv("AZURE_CLIENT_ID")
        self._client_secret = os.getenv("AZURE_CLIENT_SECRET")
        self._token_file = self._discover_federated_token_file(
            os.getenv("AZURE_FEDERATED_TOKEN_FILE")
        )

    def _discover_federated_token_file(
        self, configured_path: Optional[str]
    ) -> Optional[str]:
        """Resolve the location of the federated token for workload identity."""

        candidate_paths: List[str] = [
            "/var/run/secrets/azure/tokens/azure-identity-token",
            "/var/run/secrets/azure/tokens/azure-identity/token",
            "/var/run/secrets/workload-identity/token",
        ]
        if configured_path and configured_path not in candidate_paths:
            candidate_paths.append(configured_path)

        for path in candidate_paths:
            if not path:
                continue
            if os.path.exists(path):
                # Ensure downstream consumers see the detected path.
                os.environ["AZURE_FEDERATED_TOKEN_FILE"] = path
                if path != configured_path:
                    logger.info("Detected Azure federated token file at %s", path)
                return path

        if configured_path:
            logger.warning(
                "Configured AZURE_FEDERATED_TOKEN_FILE=%s does not exist",
                configured_path,
            )
        else:
            logger.debug("No federated token file detected for workload identity")
        return configured_path

    def get_credential(
        self,
    ) -> Optional[
        Union[
            WorkloadIdentityCredential,
            ManagedIdentityCredential,
            ClientSecretCredential,
            DefaultAzureCredential,
        ]
    ]:
        """Get Azure credential with fallback chain.

        Authentication priority:
        1. Workload Identity (WorkloadIdentityCredential with federated token)
        2. Managed Identity (ManagedIdentityCredential with AZURE_CLIENT_ID)
        3. Service Principal (ClientSecretCredential)
        4. DefaultAzureCredential (as last resort)

        Returns:
            Azure credential instance or None if authentication fails
        """
        if self._credential is not None:
            return self._credential

        # Priority 1: Workload Identity with federated token file
        # This is the proper method for AKS with workload identity
        if all([self._tenant_id, self._client_id, self._token_file]):
            try:
                logger.info(
                    f"Attempting workload identity authentication with federated token"
                )
                logger.info(f"  tenant_id: {self._tenant_id}")
                client_preview = self._client_id[:8] if self._client_id else "unknown"
                logger.info(f"  client_id: {client_preview}...")
                logger.info(f"  token_file: {self._token_file}")

                # Check if token file exists
                token_path = self._token_file
                if token_path and os.path.exists(token_path):
                    logger.info(f"✓ Token file exists at {token_path}")
                else:
                    logger.warning(f"⚠ Token file not found at {token_path}")

                self._credential = WorkloadIdentityCredential(
                    tenant_id=self._tenant_id,
                    client_id=self._client_id,
                    token_file_path=self._token_file,
                )
                # Test the credential by getting a token
                self._credential.get_token("https://storage.azure.com/.default")
                logger.info(
                    "✓ Successfully authenticated using workload identity with federated token"
                )
                return self._credential
            except Exception as e:
                logger.warning(
                    f"Workload identity (federated token) authentication failed: {e}"
                )
                self._credential = None

        # Priority 2: Managed Identity with explicit client ID (fallback for IMDS-based auth)
        if self._client_id and not self._client_secret:
            try:
                logger.info(
                    f"Attempting managed identity authentication with client_id: {self._client_id[:8]}..."
                )
                self._credential = ManagedIdentityCredential(client_id=self._client_id)
                # Test the credential by getting a token
                self._credential.get_token("https://storage.azure.com/.default")
                logger.info("✓ Successfully authenticated using managed identity")
                return self._credential
            except Exception as e:
                logger.warning(f"Managed identity authentication failed: {e}")
                self._credential = None

        # Priority 3: Service Principal (explicit credentials)
        if all([self._tenant_id, self._client_id, self._client_secret]):
            try:
                logger.info("Attempting service principal authentication")
                self._credential = ClientSecretCredential(
                    tenant_id=str(self._tenant_id),
                    client_id=str(self._client_id),
                    client_secret=str(self._client_secret),
                )
                # Test the credential
                self._credential.get_token("https://storage.azure.com/.default")
                logger.info("✓ Successfully authenticated using service principal")
                return self._credential
            except Exception as e:
                logger.warning(f"Service principal authentication failed: {e}")
                self._credential = None

        # Priority 4: DefaultAzureCredential as fallback (less reliable in K8s)
        try:
            logger.info("Attempting DefaultAzureCredential (may be slow in Kubernetes)")
            self._credential = DefaultAzureCredential(
                exclude_interactive_browser_credential=True,
                exclude_powershell_credential=True,
                exclude_visual_studio_code_credential=True,
            )
            # Test the credential
            self._credential.get_token("https://storage.azure.com/.default")
            logger.info("✓ Successfully authenticated using DefaultAzureCredential")
            return self._credential
        except Exception as e:
            logger.error(f"DefaultAzureCredential failed: {e}")
            self._credential = None

        logger.error("❌ All authentication methods failed")
        return None

    def test_connectivity(
        self,
        storage_account_name: str,
        subscription_id: str,
        resource_group: str,
        workspace_name: str,
    ) -> dict:
        """Test connectivity to Azure services.

        Args:
            storage_account_name: Azure Storage account name
            subscription_id: Azure subscription ID
            resource_group: Resource group name
            workspace_name: ML workspace name

        Returns:
            Dictionary with connectivity test results
        """
        results = {
            "credential": False,
            "storage": False,
            "ml_workspace": False,
            "errors": [],
        }

        # Test credential
        credential = self.get_credential()
        if credential is None:
            results["errors"].append("Failed to obtain Azure credential")
            return results
        results["credential"] = True

        # Test Storage connectivity
        try:
            account_url = f"https://{storage_account_name}.blob.core.windows.net/"
            blob_client = BlobServiceClient(
                account_url=account_url, credential=credential
            )
            # Test by trying to list containers (minimal operation)
            list(blob_client.list_containers(max_results=1))
            results["storage"] = True
            logger.info("Azure Storage connectivity verified")
        except Exception as e:
            error_msg = f"Azure Storage connectivity failed: {e}"
            results["errors"].append(error_msg)
            logger.error(error_msg)

        # Test ML workspace connectivity
        if MLClient is not None:
            try:
                ml_client = MLClient(
                    credential=credential,
                    subscription_id=subscription_id,
                    resource_group_name=resource_group,
                    workspace_name=workspace_name,
                )
                # Test by getting workspace details
                ml_client.workspaces.get(workspace_name)
                results["ml_workspace"] = True
                logger.info("Azure ML workspace connectivity verified")
            except Exception as e:
                error_msg = f"Azure ML workspace connectivity failed: {e}"
                results["errors"].append(error_msg)
                logger.error(error_msg)
        else:
            results["errors"].append("Azure ML SDK not available")
            logger.warning(
                "Azure ML SDK not installed, skipping ML workspace connectivity test"
            )

        return results

    def validate_environment(self) -> bool:
        """Validate required environment variables are set.

        Returns:
            True if environment is properly configured
        """
        required_vars = [
            "AZURE_SUBSCRIPTION_ID",
            "AZURE_RESOURCE_GROUP",
            "AZURE_ML_WORKSPACE_NAME",
            "AZURE_STORAGE_ACCOUNT_NAME",
        ]

        missing_vars = []
        for var in required_vars:
            if not os.getenv(var):
                missing_vars.append(var)

        if missing_vars:
            logger.error(f"Missing required environment variables: {missing_vars}")
            return False

        # Check for authentication variables (at least one method should be available)
        auth_methods = [
            # Service Principal
            all(
                [
                    os.getenv("AZURE_CLIENT_ID"),
                    os.getenv("AZURE_TENANT_ID"),
                    os.getenv("AZURE_CLIENT_SECRET"),
                ]
            ),
            # Managed Identity (AZURE_CLIENT_ID can be used for user-assigned MI)
            os.getenv("AZURE_CLIENT_ID") and not os.getenv("AZURE_CLIENT_SECRET"),
        ]

        if not any(auth_methods):
            logger.warning(
                "No explicit authentication method configured, relying on DefaultAzureCredential"
            )

        return True


def get_authenticated_blob_client(
    storage_account_name: str,
) -> Optional[BlobServiceClient]:
    """Get authenticated blob service client.

    Args:
        storage_account_name: Azure Storage account name

    Returns:
        BlobServiceClient instance or None if authentication fails
    """
    authenticator = AzureAuthenticator()
    credential = authenticator.get_credential()

    if credential is None:
        logger.error("Failed to get Azure credential for blob client")
        return None

    try:
        account_url = f"https://{storage_account_name}.blob.core.windows.net/"
        return BlobServiceClient(account_url=account_url, credential=credential)
    except Exception as e:
        logger.error(f"Failed to create blob service client: {e}")
        return None


def get_authenticated_ml_client(
    subscription_id: str, resource_group: str, workspace_name: str
):
    """Get authenticated ML client.

    Args:
        subscription_id: Azure subscription ID
        resource_group: Resource group name
        workspace_name: ML workspace name

    Returns:
        MLClient instance or None if authentication fails
    """
    if MLClient is None:
        logger.error("Azure ML SDK not available")
        return None

    authenticator = AzureAuthenticator()
    credential = authenticator.get_credential()

    if credential is None:
        logger.error("Failed to get Azure credential for ML client")
        return None

    try:
        return MLClient(
            credential=credential,
            subscription_id=subscription_id,
            resource_group_name=resource_group,
            workspace_name=workspace_name,
        )
    except Exception as e:
        logger.error(f"Failed to create ML client: {e}")
        return None
