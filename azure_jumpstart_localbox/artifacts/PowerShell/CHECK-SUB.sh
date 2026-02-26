#!/usr/bin/env bash

# Check for az CLI
if ! command -v az &> /dev/null; then
  echo "❌ Azure CLI (az) is not installed. Please install it before running this script."
  exit 1
fi

# Usage/help function
usage() {
  echo "Usage: $0 [--subscription db768a42-1846-461b-b405-76396ffc8a1a]"
  exit 1
}

# Parse optional argument
subscription=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --subscription) subscription="$2"; shift ;;
    -h|--help) usage ;;
    *) echo "❗ Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

if [[ -z "$subscription" ]]; then
  read -p "Enter your Azure subscription ID or name: " subscription
fi

if ! az account set --subscription "$subscription" 2>/dev/null; then
  echo "❌ Failed to set subscription '$subscription'. Please check the subscription ID/name and try again."
  exit 1
fi

echo "✅ Using subscription: $(az account show --query name -o tsv)"

# Define an array of namespace and feature flag pairs
features=(
  "Microsoft.EdgeOrder GePrivatePreview"
  "Microsoft.Edge PreviewAccess"
  "Microsoft.DeviceOnboarding DefaultFeature"
  "Microsoft.AzureStackHCI HiddenPreviewAccess"
  "Microsoft.ExtendedLocation CustomLocations-EdgeCluster"
  "Microsoft.ContainerService EnableNamespaceResourcesPreview"
  "Microsoft.KubernetesConfiguration extensions"
  "Microsoft.KubernetesConfiguration ExtensionTypes"
  "Microsoft.KubernetesConfiguration namespaces"
  "Microsoft.Kubernetes previewAccess"
  "Microsoft.HybridContainerService hiddenPreviewAccess"
  "Microsoft.HybridConnectivity hiddenPreviewAccess"
  "Microsoft.DeviceOnboarding AzureLocalZTP"
)

# Print table header
printf "| %-35s | %-35s | %-20s |\n" "Resource Provider" "Feature Flag" "Status"
printf "|-%-35s-|-%-35s-|-%-20s-|\n" "$(printf '%.0s-' {1..35})" "$(printf '%.0s-' {1..35})" "$(printf '%.0s-' {1..20})"

# Loop through each feature and get its status
for entry in "${features[@]}"; do
  namespace=$(echo $entry | awk '{print $1}')
  feature=$(echo $entry | awk '{print $2}')
  status=$(az feature show --namespace "$namespace" --name "$feature" --query "properties.state" -o tsv 2>/dev/null)
  
  # Color code the status for better visibility
  if [[ "$status" == "Registered" ]]; then
    status="✅ $status"
  elif [[ "$status" == "Registering" ]]; then
    status="⏳ $status"
  elif [[ -z "$status" ]]; then
    status="❌ Not Found"
  fi
  
  printf "| %-35s | %-35s | %-20s |\n" "$namespace" "$feature" "$status"
done

echo ""
echo "Legend: ✅ Registered | ⏳ Registering | ❌ Not Found"
