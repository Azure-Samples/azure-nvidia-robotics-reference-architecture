"""Azure integration managers for Isaac Lab RSL-RL training.

This module provides Azure Storage and Azure ML integration for training logs,
experiment tracking, and model checkpoint management.
"""

import json
import logging
import os
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from azure.core.exceptions import AzureError
from azure.storage.blob import BlobServiceClient, BlobClient
from azure.storage.blob.aio import BlobServiceClient as AsyncBlobServiceClient

AZURE_MLFLOW_DOC_LINK = "https://learn.microsoft.com/en-us/azure/machine-learning/how-to-use-mlflow-configure-tracking"

try:
    from azure.ai.ml import MLClient
    from azure.ai.ml.entities import Model, Experiment
    from azure.ai.ml.constants import AssetTypes
    import mlflow
except ImportError:
    MLClient = None
    Model = None
    Experiment = None
    AssetTypes = None
    mlflow = None

AZUREML_MLFLOW_AVAILABLE = False
if mlflow is not None:
    try:
        import azureml.mlflow  # noqa: F401  # Ensures AzureML MLflow plugin is registered

        AZUREML_MLFLOW_AVAILABLE = True
    except ImportError:
        AZUREML_MLFLOW_AVAILABLE = False

from .utils.auth_helpers import (
    get_authenticated_blob_client,
    get_authenticated_ml_client,
)

logger = logging.getLogger(__name__)


class AzureStorageManager:
    """Manages Azure Storage operations for training logs and outputs."""

    def __init__(
        self,
        storage_account_name: str,
        container_name: str = "isaaclab-training-logs",
        upload_interval: int = 300,
        local_backup: bool = True,
    ):
        """Initialize Azure Storage manager.

        Args:
            storage_account_name: Azure Storage account name
            container_name: Blob container name for storing training data
            upload_interval: Interval in seconds for background uploads
            local_backup: Whether to maintain local backups
        """
        self.storage_account_name = storage_account_name
        self.container_name = container_name
        self.upload_interval = upload_interval
        self.local_backup = local_backup
        self.blob_client = None
        self._upload_thread = None
        self._stop_uploads = False
        self._upload_queue: List[Dict[str, Any]] = []
        self._queue_lock = threading.Lock()

        # Initialize blob client
        self._initialize_blob_client()

    def _initialize_blob_client(self) -> bool:
        """Initialize blob service client.

        Returns:
            True if initialization successful
        """
        try:
            logger.info(
                f"Initializing Azure Storage client for account: {self.storage_account_name}"
            )
            self.blob_client = get_authenticated_blob_client(self.storage_account_name)
            if self.blob_client is None:
                logger.error("Failed to get authenticated blob client")
                return False

            # Test connectivity by listing containers
            try:
                logger.info("Testing Azure Storage connectivity...")
                containers = list(self.blob_client.list_containers(max_results=1))
                logger.info(
                    f"✓ Azure Storage connectivity verified (found {len(containers)} container(s))"
                )
            except Exception as e:
                logger.warning(f"Storage connectivity test failed: {e}")
                # Don't fail initialization - container might not exist yet
                pass

            # Ensure container exists
            try:
                self.blob_client.create_container(self.container_name)
                logger.info(f"✓ Created container: {self.container_name}")
            except Exception as e:
                # Container might already exist, check if we can access it
                try:
                    container_client = self.blob_client.get_container_client(
                        self.container_name
                    )
                    if container_client.exists():
                        logger.info(
                            f"✓ Container {self.container_name} already exists and is accessible"
                        )
                    else:
                        logger.error(
                            f"Container {self.container_name} does not exist and could not be created"
                        )
                        return False
                except Exception as access_error:
                    logger.error(
                        f"Cannot access container {self.container_name}: {access_error}"
                    )
                    return False

            logger.info(
                f"✓ Azure Storage client initialized for account: {self.storage_account_name}"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to initialize Azure Storage client: {e}")
            import traceback

            logger.error(traceback.format_exc())
            return False

    def start_background_sync(self):
        """Start background thread for log synchronization."""
        if self._upload_thread is not None:
            logger.warning("Background sync already running")
            return

        if self.blob_client is None:
            logger.error("Cannot start background sync: blob client not initialized")
            return

        self._stop_uploads = False
        self._upload_thread = threading.Thread(
            target=self._background_upload_worker, daemon=True
        )
        self._upload_thread.start()
        logger.info("Started background Azure Storage sync")

    def stop_background_sync(self):
        """Stop background thread for log synchronization."""
        if self._upload_thread is None:
            return

        self._stop_uploads = True
        self._upload_thread.join(timeout=10)
        self._upload_thread = None
        logger.info("Stopped background Azure Storage sync")

    def _background_upload_worker(self):
        """Background worker for uploading queued items."""
        while not self._stop_uploads:
            try:
                # Process upload queue
                with self._queue_lock:
                    items_to_upload = self._upload_queue.copy()
                    self._upload_queue.clear()

                for item in items_to_upload:
                    try:
                        self._upload_item(item)
                    except Exception as e:
                        logger.error(
                            f"Failed to upload item {item.get('blob_name', 'unknown')}: {e}"
                        )
                        # Re-queue failed items (with limit to prevent infinite loops)
                        if item.get("retry_count", 0) < 3:
                            item["retry_count"] = item.get("retry_count", 0) + 1
                            with self._queue_lock:
                                self._upload_queue.append(item)

                # Wait for next interval
                time.sleep(self.upload_interval)

            except Exception as e:
                logger.error(f"Error in background upload worker: {e}")
                time.sleep(30)  # Wait before retrying

    def _upload_item(self, item: Dict[str, Any]):
        """Upload a single item to Azure Storage.

        Args:
            item: Dictionary containing upload parameters
        """
        if self.blob_client is None:
            raise Exception("Blob client not initialized")

        blob_name = item["blob_name"]
        file_path = item.get("file_path")
        data = item.get("data")

        try:
            blob_client = self.blob_client.get_blob_client(
                container=self.container_name, blob=blob_name
            )

            if file_path:
                with open(file_path, "rb") as data_stream:
                    blob_client.upload_blob(data_stream, overwrite=True)
            elif data:
                blob_client.upload_blob(data, overwrite=True)
            else:
                raise ValueError("Either file_path or data must be provided")

            logger.debug(f"Uploaded blob: {blob_name}")

        except Exception as e:
            logger.error(f"Failed to upload blob {blob_name}: {e}")
            raise

    def upload_directory(
        self, local_path: str, blob_prefix: str = "", immediate: bool = False
    ):
        """Upload entire directory to Azure Storage.

        Args:
            local_path: Local directory path to upload
            blob_prefix: Prefix for blob names
            immediate: If True, upload immediately instead of queuing
        """
        local_path = Path(local_path)
        if not local_path.exists():
            logger.warning(f"Directory does not exist: {local_path}")
            return

        for file_path in local_path.rglob("*"):
            if file_path.is_file():
                relative_path = file_path.relative_to(local_path)
                blob_name = f"{blob_prefix}/{relative_path}".lstrip("/")

                item = {
                    "blob_name": blob_name,
                    "file_path": str(file_path),
                    "retry_count": 0,
                }

                if immediate:
                    try:
                        self._upload_item(item)
                    except Exception as e:
                        logger.error(f"Failed to upload {file_path}: {e}")
                else:
                    with self._queue_lock:
                        self._upload_queue.append(item)

    def upload_file(self, file_path: str, blob_name: str, immediate: bool = False):
        """Upload single file to Azure Storage.

        Args:
            file_path: Local file path
            blob_name: Blob name in storage
            immediate: If True, upload immediately instead of queuing
        """
        item = {"blob_name": blob_name, "file_path": file_path, "retry_count": 0}

        if immediate:
            try:
                self._upload_item(item)
            except Exception as e:
                logger.error(f"Failed to upload {file_path}: {e}")
        else:
            with self._queue_lock:
                self._upload_queue.append(item)

    def is_available(self) -> bool:
        """Check if Azure Storage is available.

        Returns:
            True if storage is available and accessible
        """
        return self.blob_client is not None


class AzureMLManager:
    """Manages Azure ML operations for experiment tracking and model registry."""

    def __init__(
        self,
        subscription_id: str,
        resource_group: str,
        workspace_name: str,
        tracking_uri: Optional[str] = None,
        enable_autolog: bool = True,
    ):
        """Initialize Azure ML manager.

        Args:
            subscription_id: Azure subscription ID
            resource_group: Resource group name
            workspace_name: ML workspace name
            tracking_uri: Optional MLflow tracking URI override
            enable_autolog: Whether to enable MLflow autologging
        """
        self.subscription_id = subscription_id
        self.resource_group = resource_group
        self.workspace_name = workspace_name
        self.ml_client = None
        self.current_experiment = None
        self.current_run = None
        self._tracking_uri_override = tracking_uri
        self._resolved_tracking_uri: Optional[str] = None
        self.enable_autolog = enable_autolog
        self._autolog_active = False

        # Initialize ML client
        self._initialize_ml_client()

    def _initialize_ml_client(self) -> bool:
        """Initialize ML client.

        Returns:
            True if initialization successful
        """
        if MLClient is None:
            logger.warning("Azure ML SDK not available (azure-ai-ml not installed)")
            return False

        try:
            logger.info(
                f"Initializing Azure ML client for workspace: {self.workspace_name}"
            )
            self.ml_client = get_authenticated_ml_client(
                self.subscription_id, self.resource_group, self.workspace_name
            )

            if self.ml_client is None:
                logger.error("Failed to get authenticated ML client")
                return False

            # Test connectivity by getting workspace details
            try:
                logger.info("Testing Azure ML connectivity...")
                workspace = self.ml_client.workspaces.get(self.workspace_name)
                logger.info(
                    f"✓ Azure ML connectivity verified (workspace: {workspace.name}, location: {workspace.location})"
                )
            except Exception as e:
                logger.error(f"Azure ML connectivity test failed: {e}")
                return False

            logger.info(
                f"Azure ML client initialized for workspace: {self.workspace_name}"
            )
            # Resolve tracking URI once the client is ready to avoid repeated lookups
            self._resolved_tracking_uri = self._resolve_tracking_uri(force_refresh=True)
            if not AZUREML_MLFLOW_AVAILABLE:
                logger.warning(
                    "azureml-mlflow plugin not found. Install it with `pip install azureml-mlflow` "
                    f"to enable MLflow tracking (see {AZURE_MLFLOW_DOC_LINK})."
                )
            return True

        except Exception as e:
            logger.error(f"Failed to initialize Azure ML client: {e}")
            import traceback

            logger.error(traceback.format_exc())
            return False

    def _resolve_tracking_uri(self, force_refresh: bool = False) -> Optional[str]:
        """Resolve the MLflow tracking URI for the configured workspace."""

        if self._tracking_uri_override:
            self._resolved_tracking_uri = self._tracking_uri_override
            return self._resolved_tracking_uri

        if not force_refresh and self._resolved_tracking_uri:
            return self._resolved_tracking_uri

        env_override = os.getenv("MLFLOW_TRACKING_URI")
        if env_override:
            self._resolved_tracking_uri = env_override
            return self._resolved_tracking_uri

        if self.ml_client is not None:
            try:
                workspace = self.ml_client.workspaces.get(name=self.workspace_name)
                if getattr(workspace, "mlflow_tracking_uri", None):
                    self._resolved_tracking_uri = workspace.mlflow_tracking_uri
                    return self._resolved_tracking_uri
            except Exception as exc:
                logger.warning(
                    "Failed to retrieve MLflow tracking URI from workspace API: %s", exc
                )

        region = os.getenv("AZURE_ML_WORKSPACE_REGION")
        if region:
            self._resolved_tracking_uri = (
                f"azureml://{region}.api.azureml.ms/mlflow/v1.0/"
                f"subscriptions/{self.subscription_id}/"
                f"resourceGroups/{self.resource_group}/"
                f"providers/Microsoft.MachineLearningServices/"
                f"workspaces/{self.workspace_name}"
            )
            return self._resolved_tracking_uri

        return self._resolved_tracking_uri

    def create_experiment(self, experiment_name: str, description: str = "") -> bool:
        """Create or get ML experiment.

        Args:
            experiment_name: Name of the experiment
            description: Optional description

        Returns:
            True if experiment was created/retrieved successfully
        """
        if not self.is_available():
            return False

        try:
            # Try to get existing experiment first
            try:
                experiment = self.ml_client.experiments.get(experiment_name)
                logger.info(f"Using existing experiment: {experiment_name}")
            except Exception:
                # Create new experiment
                experiment = Experiment(
                    name=experiment_name,
                    description=description,
                    tags={"created_by": "isaaclab_rsl_rl"},
                )
                experiment = self.ml_client.experiments.create_or_update(experiment)
                logger.info(f"Created new experiment: {experiment_name}")

            self.current_experiment = experiment
            return True

        except Exception as e:
            logger.error(f"Failed to create/get experiment {experiment_name}: {e}")
            return False

    def start_run(self, run_name: str, tags: Optional[Dict[str, str]] = None) -> bool:
        """Start MLflow run for tracking.

        Args:
            run_name: Name for the run
            tags: Optional tags for the run

        Returns:
            True if run started successfully
        """
        if not self.is_available() or mlflow is None:
            return False

        try:
            if self.current_experiment is None:
                logger.error("No active experiment. Create experiment first.")
                return False

            if not AZUREML_MLFLOW_AVAILABLE:
                logger.error(
                    "azureml-mlflow plugin is required for remote MLflow tracking. Install it "
                    f"with `pip install azureml-mlflow` (see {AZURE_MLFLOW_DOC_LINK})."
                )
                return False

            # Set MLflow tracking URI
            mlflow_uri = self._resolve_tracking_uri()
            if not mlflow_uri:
                logger.error(
                    "Unable to resolve MLflow tracking URI. Configure the tracking URI per %s.",
                    AZURE_MLFLOW_DOC_LINK,
                )
                return False

            mlflow.set_tracking_uri(mlflow_uri)

            # Start run
            mlflow.set_experiment(self.current_experiment.name)
            run = mlflow.start_run(run_name=run_name, tags=tags or {})
            self.current_run = run

            if self.enable_autolog and not self._autolog_active:
                try:
                    mlflow.autolog()
                    self._autolog_active = True
                    logger.info("Enabled MLflow autologging")
                except Exception as autolog_error:
                    logger.warning(
                        "Failed to enable MLflow autologging: %s", autolog_error
                    )

            logger.info(f"Started MLflow run: {run_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to start run {run_name}: {e}")
            return False

    def log_metrics(self, metrics: Dict[str, float], step: Optional[int] = None):
        """Log metrics to current run.

        Args:
            metrics: Dictionary of metric names and values
            step: Optional step number
        """
        if not self.is_available() or mlflow is None or self.current_run is None:
            return

        try:
            for name, value in metrics.items():
                mlflow.log_metric(name, value, step=step)

        except Exception as e:
            logger.error(f"Failed to log metrics: {e}")

    def log_params(self, params: Dict[str, Any]):
        """Log parameters to current run.

        Args:
            params: Dictionary of parameter names and values
        """
        if not self.is_available() or mlflow is None or self.current_run is None:
            return

        try:
            # Convert all values to strings for MLflow
            str_params = {k: str(v) for k, v in params.items()}
            mlflow.log_params(str_params)

        except Exception as e:
            logger.error(f"Failed to log parameters: {e}")

    def log_model_checkpoint(
        self,
        checkpoint_path: str,
        model_name: str,
        step: Optional[int] = None,
        metrics: Optional[Dict[str, float]] = None,
    ):
        """Log model checkpoint.

        Args:
            checkpoint_path: Path to checkpoint file
            model_name: Name for the model
            step: Optional training step
            metrics: Optional metrics associated with checkpoint
        """
        if not self.is_available() or mlflow is None or self.current_run is None:
            logger.warning("MLflow not available, skipping model checkpoint logging")
            return

        try:
            # Log as artifact
            mlflow.log_artifact(checkpoint_path, artifact_path="checkpoints")

            # Log checkpoint info
            checkpoint_info = {
                "checkpoint_path": checkpoint_path,
                "model_name": model_name,
                "timestamp": datetime.now().isoformat(),
                "step": step,
            }

            if metrics:
                checkpoint_info["metrics"] = metrics

            # Save checkpoint info as JSON
            info_path = f"{checkpoint_path}_info.json"
            with open(info_path, "w") as f:
                json.dump(checkpoint_info, f, indent=2)
            mlflow.log_artifact(info_path, artifact_path="checkpoints")

            # Clean up temp file
            if os.path.exists(info_path):
                os.remove(info_path)

            logger.info(f"Logged model checkpoint: {model_name} (step {step})")

        except Exception as e:
            logger.error(f"Failed to log model checkpoint: {e}")

    def end_run(self):
        """End current MLflow run."""
        if mlflow is not None and self.current_run is not None:
            try:
                mlflow.end_run()
                self.current_run = None
                logger.info("Ended MLflow run")
            except Exception as e:
                logger.error(f"Failed to end run: {e}")

    def register_model(
        self,
        model_path: str,
        model_name: str,
        description: str = "",
        tags: Optional[Dict[str, str]] = None,
    ) -> bool:
        """Register model in Azure ML Model Registry.

        Args:
            model_path: Path to model files
            model_name: Name for registered model
            description: Optional description
            tags: Optional tags

        Returns:
            True if model was registered successfully
        """
        if not self.is_available():
            return False

        try:
            model = Model(
                path=model_path,
                name=model_name,
                description=description,
                type=AssetTypes.CUSTOM_MODEL,
                tags=tags or {},
            )

            registered_model = self.ml_client.models.create_or_update(model)
            logger.info(
                f"Registered model: {model_name} (version {registered_model.version})"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to register model {model_name}: {e}")
            return False

    def is_available(self) -> bool:
        """Check if Azure ML is available.

        Returns:
            True if ML client is available and accessible
        """
        return self.ml_client is not None


class AzureIntegrationManager:
    """Orchestrates Azure Storage and ML operations for training integration."""

    def __init__(self, config: Dict[str, Any]):
        """Initialize Azure integration manager.

        Args:
            config: Configuration dictionary with Azure settings
        """
        self.config = config
        self.enabled = config.get("enabled", True)
        self.storage_manager = None
        self.ml_manager = None

        if not self.enabled:
            logger.info("Azure integration disabled by configuration")
            return

        # Initialize managers
        self._initialize_managers()

    def _initialize_managers(self):
        """Initialize storage and ML managers."""
        try:
            # Initialize Storage Manager
            storage_config = self.config.get("storage", {})
            if storage_config.get("enabled", True):
                self.storage_manager = AzureStorageManager(
                    storage_account_name=storage_config["account_name"],
                    container_name=storage_config.get(
                        "container_name", "isaaclab-training-logs"
                    ),
                    upload_interval=storage_config.get("upload_interval", 300),
                    local_backup=storage_config.get("local_backup", True),
                )

                # Start background sync if enabled
                if storage_config.get("background_sync", True):
                    self.storage_manager.start_background_sync()

            # Initialize ML Manager
            ml_config = self.config.get("ml", {})
            if ml_config.get("enabled", True):
                self.ml_manager = AzureMLManager(
                    subscription_id=ml_config["subscription_id"],
                    resource_group=ml_config["resource_group"],
                    workspace_name=ml_config["workspace_name"],
                    tracking_uri=ml_config.get("tracking_uri"),
                    enable_autolog=ml_config.get("enable_autolog", True),
                )

                if not self.ml_manager.is_available():
                    logger.warning(
                        "Azure ML manager could not be initialized. Verify azure-ai-ml and "
                        "azureml-mlflow are installed and configured per %s.",
                        AZURE_MLFLOW_DOC_LINK,
                    )

        except Exception as e:
            logger.error(f"Failed to initialize Azure managers: {e}")
            self.enabled = False

    def setup_experiment(
        self,
        experiment_name: str,
        run_name: str,
        params: Optional[Dict[str, Any]] = None,
        tags: Optional[Dict[str, str]] = None,
    ) -> bool:
        """Setup experiment and start run.

        Args:
            experiment_name: Name of the experiment
            run_name: Name of the run
            params: Training parameters to log
            tags: Optional tags for the run

        Returns:
            True if setup was successful
        """
        if (
            not self.enabled
            or self.ml_manager is None
            or not self.ml_manager.is_available()
        ):
            return False

        try:
            # Create experiment
            if not self.ml_manager.create_experiment(experiment_name):
                return False

            # Start run
            if not self.ml_manager.start_run(run_name, tags):
                return False

            # Log parameters
            if params:
                self.ml_manager.log_params(params)

            return True

        except Exception as e:
            logger.error(f"Failed to setup experiment: {e}")
            return False

    def log_training_metrics(
        self, metrics: Dict[str, float], step: Optional[int] = None
    ):
        """Log training metrics.

        Args:
            metrics: Dictionary of metrics
            step: Training step number
        """
        if (
            self.enabled
            and self.ml_manager is not None
            and self.ml_manager.is_available()
        ):
            self.ml_manager.log_metrics(metrics, step)

    def sync_training_logs(self, log_dir: str, experiment_name: str = ""):
        """Sync training logs to Azure Storage.

        Args:
            log_dir: Local log directory path
            experiment_name: Optional experiment name for organizing logs
        """
        if not self.enabled or self.storage_manager is None:
            return

        try:
            # Create blob prefix with timestamp and experiment name
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            blob_prefix = f"training_logs/{timestamp}"
            if experiment_name:
                blob_prefix = f"training_logs/{experiment_name}/{timestamp}"

            self.storage_manager.upload_directory(log_dir, blob_prefix)
            logger.info(f"Queued log directory for Azure sync: {log_dir}")

        except Exception as e:
            logger.error(f"Failed to sync training logs: {e}")

    def log_checkpoint(
        self,
        checkpoint_path: str,
        model_name: str,
        step: Optional[int] = None,
        metrics: Optional[Dict[str, float]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Log model checkpoint to both Azure ML and Storage.

        Args:
            checkpoint_path: Path to checkpoint file
            model_name: Name of the model
            step: Training step
            metrics: Performance metrics

        Returns:
            Optional dictionary with metadata about logged artefacts.
        """
        if not self.enabled:
            return None

        metadata: Dict[str, Any] = {
            "checkpoint_path": checkpoint_path,
            "model_name": model_name,
            "step": step,
            "metrics": metrics or {},
        }

        # Log to Azure ML
        if self.ml_manager is not None and self.ml_manager.is_available():
            self.ml_manager.log_model_checkpoint(
                checkpoint_path, model_name, step, metrics
            )
            metadata["ml_logged"] = True
        else:
            metadata["ml_logged"] = False

        # Upload to Azure Storage
        if self.storage_manager is not None:
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                blob_name = f"checkpoints/{model_name}/{timestamp}_step_{step}.pth"
                self.storage_manager.upload_file(
                    checkpoint_path, blob_name, immediate=True
                )
                logger.info(f"Uploaded checkpoint to Azure Storage: {blob_name}")
                metadata["storage_blob"] = blob_name
                metadata["storage_timestamp"] = timestamp
            except Exception as e:
                logger.error(f"Failed to upload checkpoint to storage: {e}")
                metadata["storage_blob"] = None
        else:
            metadata["storage_blob"] = None

        return metadata

    def finalize_training(self, final_model_path: Optional[str] = None):
        """Finalize training session.

        Args:
            final_model_path: Path to final trained model for registration
        """
        if not self.enabled:
            return

        try:
            # Register final model if provided
            if (
                final_model_path
                and self.ml_manager is not None
                and self.ml_manager.is_available()
            ):
                model_name = f"rsl_rl_model_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
                self.ml_manager.register_model(
                    final_model_path,
                    model_name,
                    description="Final trained model from RSL-RL",
                )

            # End ML run
            if self.ml_manager is not None and self.ml_manager.is_available():
                self.ml_manager.end_run()

            # Stop background sync
            if self.storage_manager is not None:
                self.storage_manager.stop_background_sync()

            logger.info("Finalized Azure integration for training session")

        except Exception as e:
            logger.error(f"Failed to finalize training: {e}")

    def is_available(self) -> bool:
        """Check if Azure integration is available.

        Returns:
            True if at least one Azure service is available
        """
        if not self.enabled:
            return False

        storage_available = (
            self.storage_manager is not None and self.storage_manager.is_available()
        )
        ml_available = self.ml_manager is not None and self.ml_manager.is_available()

        return storage_available or ml_available
