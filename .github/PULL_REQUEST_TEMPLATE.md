# Pull Request

## Description

<!-- Brief description of changes. Link related issues using Closes #123 -->

Closes #

## Type of Change
<!-- Mark relevant options with [x] -->

- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] 💥 Breaking change (fix or feature causing existing functionality to change)
- [ ] 📚 Documentation update
- [ ] 🏗️ Infrastructure change (Terraform/IaC)
- [ ] ♻️ Refactoring (no functional changes)

## Component(s) Affected
<!-- Mark all that apply -->

- [ ] `deploy/000-prerequisites` - Azure subscription setup
- [ ] `deploy/001-iac` - Terraform infrastructure
- [ ] `deploy/002-setup` - OSMO control plane / Helm
- [ ] `deploy/004-workflow` - Training workflows
- [ ] `src/training` - Python training scripts
- [ ] `docs/` - Documentation

## Testing Performed
<!-- Describe testing. Check applicable items -->

- [ ] Terraform `plan` reviewed (no unexpected changes)
- [ ] Terraform `apply` tested in dev environment
- [ ] Training scripts tested locally with Isaac Sim
- [ ] OSMO workflow submitted successfully
- [ ] Smoke tests passed (`smoke_test_azure.py`)

## Documentation Impact
<!-- Select one -->

- [ ] No documentation changes needed
- [ ] Documentation updated in this PR
- [ ] Documentation issue filed

## Checklist

- [ ] My code follows the [project conventions](copilot-instructions.md)
- [ ] Commit messages follow [conventional commit format](instructions/commit-message.instructions.md)
- [ ] I have performed a self-review
- [ ] Documentation impact assessed above
- [ ] No new linting warnings introduced
