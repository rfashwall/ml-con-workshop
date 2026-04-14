# Module 0: Environment Setup

Follow the full wiki guide: **[Module 0: Environment Setup](../../../../wiki/Module-0)**.

This directory holds the kind cluster config and a verification script. The actual setup steps (installing Python, Go, Docker, kubectl, kind, etc.) live in the wiki because they're platform-specific.

## Files

| File | Purpose |
|---|---|
| `kind.yaml` | kind cluster config used by Module 0 and onward |
| `verify-setup.sh` | Prints versions of required tools and checks the kind cluster |

## Create the cluster

```bash
kind create cluster --config kind.yaml
kubectl cluster-info --context kind-mlops-workshop
```

## Verify your setup

```bash
# macOS / Linux / WSL
bash verify-setup.sh
```

On Windows, run this from your WSL 2 Ubuntu shell, not from `cmd.exe` / PowerShell.

## Tear down

```bash
kind delete cluster --name mlops-workshop
```
