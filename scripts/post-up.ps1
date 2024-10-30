$tools = @("az")

foreach ($tool in $tools) {
  if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
    Write-Host "Error: $tool command line tool is not available, check pre-requisites in README.md"
    exit 1
  }
}

#Get the function blobs_extension key
$blobs_extension=$(az functionapp keys list -n ${env:AZURE_PROCESSOR_FUNCTION_APP_NAME} -g ${env:RESOURCE_GROUP} --query "systemKeys.blobs_extension" -o tsv)

# Build the endpoint URL with the function name and extension key and create the event subscription
# Double quotes added here to allow the az command to work successfully. Quoting inside az command had issues.
$endpointUrl="""https://" + ${env:AZURE_PROCESSOR_FUNCTION_APP_NAME} + ".azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.AudioBlobUploadStart&code=" + $blobs_extension + """"

$filter="/blobServices/default/containers/" + ${env:AUDIOS_STORAGE_ACCOUNT_CONTAINER_NAME}

az eventgrid system-topic event-subscription create -n audio-files-topic-subscription -g ${env:RESOURCE_GROUP} --system-topic-name ${env:AUDIOS_EVENTGRID_SYSTEM_TOPIC_NAME} --endpoint-type webhook --endpoint $endpointUrl --included-event-types Microsoft.Storage.BlobCreated --subject-begins-with $filter

Write-Output "Created blob event grid subscription successfully."

# Load azd environment variables to .env file for testing deployed functions
azd env get-values > .env
