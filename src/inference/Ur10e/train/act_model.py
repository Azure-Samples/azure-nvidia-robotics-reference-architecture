"""Standalone ACT (Action Chunking with Transformers) model.

Implements the architecture from Zhao et al., 2023:
"Learning Fine-Grained Bimanual Manipulation with Low-Cost Hardware"

Pure PyTorch implementation — no external ML framework dependencies.
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import models


class SinusoidalPositionEmbedding2D(nn.Module):
    """2D sinusoidal position embedding for spatial image features."""

    def __init__(self, dim: int) -> None:
        super().__init__()
        self.dim = dim

    def forward(self, h: int, w: int, device: torch.device) -> torch.Tensor:
        half = self.dim // 4
        emb = math.log(10000) / max(half - 1, 1)
        emb = torch.exp(torch.arange(half, device=device, dtype=torch.float32) * -emb)

        pos_h = torch.arange(h, device=device, dtype=torch.float32).unsqueeze(1) * emb.unsqueeze(0)
        pos_w = torch.arange(w, device=device, dtype=torch.float32).unsqueeze(1) * emb.unsqueeze(0)

        pos_h = torch.cat([pos_h.sin(), pos_h.cos()], dim=-1)
        pos_w = torch.cat([pos_w.sin(), pos_w.cos()], dim=-1)

        pos = torch.cat([
            pos_h.unsqueeze(1).expand(-1, w, -1),
            pos_w.unsqueeze(0).expand(h, -1, -1),
        ], dim=-1)

        return pos.reshape(h * w, self.dim)


class ACTModel(nn.Module):
    """Action Chunking with Transformers.

    Architecture:
        - ResNet18 vision backbone
        - CVAE encoder for training-time action encoding
        - Transformer encoder for multi-modal observation fusion
        - Transformer decoder with learned action queries
    """

    def __init__(
        self,
        state_dim: int = 6,
        action_dim: int = 6,
        chunk_size: int = 100,
        dim_model: int = 512,
        n_heads: int = 8,
        dim_feedforward: int = 3200,
        n_encoder_layers: int = 4,
        n_decoder_layers: int = 1,
        n_vae_encoder_layers: int = 4,
        latent_dim: int = 32,
        dropout: float = 0.1,
        use_vae: bool = True,
        vision_backbone: str = "resnet18",
        pretrained_backbone: bool = True,
    ) -> None:
        super().__init__()

        self.state_dim = state_dim
        self.action_dim = action_dim
        self.chunk_size = chunk_size
        self.dim_model = dim_model
        self.latent_dim = latent_dim
        self.use_vae = use_vae

        # --- Vision backbone (ResNet18) ---
        if vision_backbone == "resnet18":
            weights = models.ResNet18_Weights.IMAGENET1K_V1 if pretrained_backbone else None
            backbone = models.resnet18(weights=weights)
        else:
            raise ValueError(f"Unsupported backbone: {vision_backbone}")

        self.backbone = nn.Sequential(
            backbone.conv1, backbone.bn1, backbone.relu, backbone.maxpool,
            backbone.layer1, backbone.layer2, backbone.layer3, backbone.layer4,
        )
        backbone_out_dim = 512  # ResNet18 layer4 channels

        self.img_proj = nn.Conv2d(backbone_out_dim, dim_model, kernel_size=1)
        self.pos_embed_2d = SinusoidalPositionEmbedding2D(dim_model)

        # --- Proprioception encoder ---
        self.state_proj = nn.Linear(state_dim, dim_model)

        # --- CVAE (training only) ---
        if use_vae:
            self.cls_token = nn.Parameter(torch.zeros(1, 1, dim_model))
            nn.init.normal_(self.cls_token, std=0.02)
            self.action_proj = nn.Linear(action_dim, dim_model)
            vae_layer = nn.TransformerEncoderLayer(
                d_model=dim_model, nhead=n_heads,
                dim_feedforward=dim_feedforward, dropout=dropout,
                activation="relu", batch_first=True,
            )
            self.vae_encoder = nn.TransformerEncoder(vae_layer, num_layers=n_vae_encoder_layers)
            self.mu_proj = nn.Linear(dim_model, latent_dim)
            self.logvar_proj = nn.Linear(dim_model, latent_dim)

        # --- Latent projection ---
        self.latent_proj = nn.Linear(latent_dim, dim_model)

        # --- Transformer encoder ---
        enc_layer = nn.TransformerEncoderLayer(
            d_model=dim_model, nhead=n_heads,
            dim_feedforward=dim_feedforward, dropout=dropout,
            activation="relu", batch_first=True,
        )
        self.encoder = nn.TransformerEncoder(enc_layer, num_layers=n_encoder_layers)

        # --- Transformer decoder ---
        dec_layer = nn.TransformerDecoderLayer(
            d_model=dim_model, nhead=n_heads,
            dim_feedforward=dim_feedforward, dropout=dropout,
            activation="relu", batch_first=True,
        )
        self.decoder = nn.TransformerDecoder(dec_layer, num_layers=n_decoder_layers)

        # --- Action queries + head ---
        self.action_queries = nn.Embedding(chunk_size, dim_model)
        self.action_head = nn.Linear(dim_model, action_dim)

    def encode_image(self, image: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        """Encode image through ResNet18 backbone.

        Args:
            image: (B, 3, H, W) normalised image tensor.

        Returns:
            features (B, H'*W', dim_model) and pos_embed (H'*W', dim_model).
        """
        feat = self.backbone(image)            # (B, 512, H', W')
        feat = self.img_proj(feat)             # (B, dim, H', W')
        _, _, fh, fw = feat.shape
        feat = feat.flatten(2).permute(0, 2, 1)  # (B, H'*W', dim)
        pos = self.pos_embed_2d(fh, fw, feat.device)
        return feat, pos

    def forward(
        self,
        state: torch.Tensor,
        image: torch.Tensor,
        actions: torch.Tensor | None = None,
    ) -> tuple[torch.Tensor, tuple[torch.Tensor, torch.Tensor] | None]:
        """Forward pass.

        Args:
            state:   (B, state_dim)
            image:   (B, 3, H, W)
            actions: (B, chunk_size, action_dim) — only during training.

        Returns:
            pred_actions (B, chunk_size, action_dim) and optional (mu, logvar).
        """
        B = state.shape[0]
        device = state.device

        img_feat, img_pos = self.encode_image(image)
        img_feat = img_feat + img_pos.unsqueeze(0)
        state_embed = self.state_proj(state).unsqueeze(1)  # (B, 1, dim)

        mu = logvar = None
        if self.use_vae and actions is not None:
            act_embed = self.action_proj(actions)
            cls = self.cls_token.expand(B, -1, -1)
            vae_in = torch.cat([cls, state_embed, img_feat, act_embed], dim=1)
            vae_out = self.vae_encoder(vae_in)
            cls_out = vae_out[:, 0]
            mu = self.mu_proj(cls_out)
            logvar = self.logvar_proj(cls_out)
            std = torch.exp(0.5 * logvar)
            z = mu + torch.randn_like(std) * std
        else:
            z = torch.zeros(B, self.latent_dim, device=device)

        z_embed = self.latent_proj(z).unsqueeze(1)
        encoder_in = torch.cat([z_embed, state_embed, img_feat], dim=1)
        encoder_out = self.encoder(encoder_in)

        queries = self.action_queries.weight.unsqueeze(0).expand(B, -1, -1)
        decoder_out = self.decoder(queries, encoder_out)
        pred_actions = self.action_head(decoder_out)

        if self.use_vae and mu is not None:
            return pred_actions, (mu, logvar)
        return pred_actions, None

    @staticmethod
    def compute_loss(
        pred: torch.Tensor,
        target: torch.Tensor,
        mu: torch.Tensor | None = None,
        logvar: torch.Tensor | None = None,
        kl_weight: float = 10.0,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """ACT loss: L1 reconstruction + KL divergence.

        Returns (total_loss, l1_loss, kl_loss).
        """
        l1 = F.l1_loss(pred, target)
        kl = torch.tensor(0.0, device=pred.device)
        if mu is not None and logvar is not None:
            kl = -0.5 * torch.mean(1 + logvar - mu.pow(2) - logvar.exp())
        return l1 + kl_weight * kl, l1, kl
