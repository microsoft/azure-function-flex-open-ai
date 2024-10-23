---
published: true
type: workshop
title: Build serverless intelligent Apps with Azure Functions Flex Consumption and extension for OpenAI
short_title: Intelligent app with Flex Consumption and Azure OpenAI
description: In this workshop you will learn how to build an intelligent application that summarizes audio files using Azure Functions Flex Consumption and Azure OpenAI
level: beginner # Required. Can be 'beginner', 'intermediate' or 'advanced'
navigation_numbering: false
authors: # Required. You can add as many authors as needed
  - Damien Aicheh
  - Iheb Khemissi
contacts: # Required. Must match the number of authors
  - "@damienaicheh"
  - "@ikhemissi"
duration_minutes: 60
tags: azure, azure functions, durable function, flex consumption, azure openai, entra id, cosmos db, csu, codespace, devcontainer, ignite
navigation_levels: 3
---

# Build serverless intelligent Apps with Azure Functions Flex Consumption and extension for OpenAI

Welcome to this Azure Functions Workshop. You'll be experimenting with Azure Functions service in multiple labs to achieve a real world scenario. You will use the Azure Functions Flex consumption plan for all of these labs which contains the latest features of Azure Functions. Don't worry, this is a step by step lab, you will be guided through the whole process.

During this workshop you will have the instructions to complete each steps. The solutions are placed under the 'Toggle solution' panel.

<div class="task" data-title="Task">

> - You will find the instructions and expected configurations for each Lab step in these yellow **TASK** boxes.
> - Log into your Azure subscription locally using Azure CLI and on the [Azure Portal][az-portal] using the credentials provided to you.
> - In this version of the implementation, you will be using the [.NET 8 Isolated][in-process-vs-isolated] runtime.

</div>


## Scenario

The goal of the full lab is to upload an audio file to Azure and save the transcripts back inside a Cosmos DB database and enrich these transcriptions with a summary using Azure OpenAI. The scenario is as follows:

![Hand's On Lab Architecture](assets/architecture-overview.png)

1. The first Azure Function (standard function) will be mainly responsible for uploading the audio file to the Storage Account.
1. Whenever a blob is uploaded to the Storage Account, a `BlobCreated` event will be emitted to Event Grid
1. The Event Grid System Topic will push the event (in real time) to trigger the Azure Durable Function
1. The Azure Durable Function will start processing the audio file
1. The Azure Durable Function will use the Speech To Text service for audio transcription. It will use the Monitor pattern to check every few seconds if the transcription is done.
1. The Azure Durable Function will retrieve the transcription from the Speech to Text service
1. The Azure Durable Function will use Azure OpenAI to generate a summary of the audio file from the transcription
1. The Azure Durable Function will then store the transcription and its summary in Cosmos DB

## Sign in to Azure

To retrieve the lab content :

<div class="task" data-title="Task">

> - On your Desktop, [Clone][repo-clone] the repository from the **main** branch or [fork it][repo-fork] if you want to keep track of your changes if you have a GitHub account.
> - Open the project inside VS Code
> - Log into the provided Azure subscription in your environment using Azure CLI and on the [Azure Portal][az-portal] using your credentials.

</div>

<details>

<summary> Toggle solution</summary>

```bash
# Login to Azure : 
az login
# Display your account details
az account show
# Select your Azure subscription
az account set --subscription <subscription-id>
```

</details>

[az-portal]: https://portal.azure.com
[repo-clone]: https://github.com/microsoft/hands-on-lab-azure-functions-flex-openai
[repo-fork]: https://github.com/microsoft/hands-on-lab-azure-functions-flex-openai/fork
[in-process-vs-isolated]: https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-in-process-differences

---

# Lab 1 : Configure the environment

In this first lab you will setup the environment to make sure everything is working as expected.

## Deploy to Azure

The Azure Developer CLI (azd) is an open-source tool that accelerates your path from a local development environment to Azure. It provides a set of developer-friendly commands that map to key stages in your workflow (code, build, deploy, monitor).

To initialize azd you should first authenficate with azd:

```sh
azd auth login
```

Create an environment called `dev`, keep this name as it will be used to target pre-deployed resources:

```sh
azd env new dev
```

Inside the `.azure/dev` folder generated, update the `.env` file with the following values and make sure to update it depending on your Azure resources:

```sh
AZURE_SUBSCRIPTION_ID="<TO-UPDATE>"
RESOURCE_GROUP="rg-lab-<TO-UPDATE>"
AZURE_UPLOADER_FUNCTION_APP_NAME="func-std-<TO-UPDATE>"
AZURE_PROCESSOR_FUNCTION_APP_NAME="func-drbl-<TO-UPDATE>"
AUDIOS_EVENTGRID_SYSTEM_TOPIC_NAME="evgt-<TO-UPDATE>"
AUDIOS_STORAGE_ACCOUNT_CONTAINER_NAME="audios"
AZURE_ENV_NAME="dev"
AZURE_LOCATION="eastus2"
```

Now you can deploy the functions code:

```sh
azd deploy
```

In case of issues, you can also deploy the functions manually using the Azure Functions extension in VS Code:

- Open the Azure extension in VS Code left panel
- Make sure you're signed in to your Azure account
- Open the Function App panel
- Right-click on your function app inside `src/uploader` and select `Deploy to Function App...`
- Select the Function starting with `func-std-`
- Right-click on your function app inside `src/processor` and select `Deploy to Function App...`
- Select the Function starting with `func-drbl-`

![Deploy to Function App](assets/function-app-deploy.png)

## Audio files

Open the [Azure Portal][az-portal] and go to your resource group inside your subscription and select the storage account which is starting with `sto`. You will use it to upload the audios files inside the `audios` container later in the labs:

![Storage account access keys](assets/storage-account-show-container.png)

Keep this page open you will need it later to upload your audios to test the different labs.

You can use one of the sample audio files provided in the workshop:

- [Microsoft AI](assets/audios/MicrosoftAI.wav)
- [Azure Functions](assets/audios/AzureFunctions.wav)

Just click on each link and download the file.

</details>

## Lab 1 : Summary

By now you should be ready to deploy the new updates of your Azure Functions for the next labs.

[az-portal]: https://portal.azure.com
[azure-function-core-tools]: https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=v4%2Cwindows%2Ccsharp%2Cportal%2Cbash
[in-process-vs-isolated]: https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-in-process-differences
[azure-storage-extension]: https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurestorage#:~:text=Installation.%20Download%20and%20install%20the%20Azure%20Storage%20extension%20for%20Visual
[postman]: https://www.postman.com/

---

# Lab 2 : Speech to text transcription

In this lab, you will focus on the following scope :

![Hand's On Lab Architecture Lab](assets/azure-functions-lab2.png)

Processing the audio file involves the following actions:
- Detecting file uploads
- Creating a transcript of the file
- Saving the transcript to Azure Cosmos DB
- Generating a summary with Azure OpenAI

To ensure the execution of all these steps and to orchestrate all of this process, you will need a Durable Function which is already created for you in `src/processor`.

Durable Function is an extension of Azure Functions that lets you write stateful functions in a serverless environment. This extension manages state, checkpoints, and restarts for you.

## Detect a file upload event 

Now, you have the audio file uploaded in the storage account. To detect when a new audio is uploaded in the Storage Account an `Event Grid System Topic` was created for you. This Event Grid Subscription listen to the event of uploading in your `audios` container based on this configuration:

- Filter to Event Types: `Blob Created`
- A **Web Hook** event was already created for you, which is targetting the Azure Durable function to trigger the `AudioBlobUploadStart` method.
- This event is only triggerd for `.wav` files

## Consume Speech to Text APIs

The Azure Cognitive Services are cloud-based AI services that give the ability to developers to quickly build intelligent apps thanks to these pre-trained models. They are available through client library SDKs in popular development languages and REST APIs.

Cognitive Services can be categorized into five main areas:

- **Decision:** Content Moderator provides monitoring for possible offensive, undesirable, and risky content. Anomaly Detector allows you to monitor and detect abnormalities in your time series data.
- **Language:** Azure Language service provides several Natural Language Processing (NLP) features to understand and analyze text.
- **Speech:** Speech service includes various capabilities like speech to text, text to speech, speech translation, and many more.
- **Vision:** The Computer Vision service provides you with access to advanced cognitive algorithms for processing images and returning information.
- **Azure OpenAI Service:** Powerful language models including for instance the GPT-3, GPT-4, Codex and Embeddings model series for content generation, summarization, semantic search, natural language to code translation and much more.

You now want to retrieve the transcript out of the audio file uploaded thanks to the speech to text cognitive service.

<div class="task" data-title="Tasks">

> - Because the transcription can be a long process, you will use the monitor pattern of the Azure Durable Functions to call the speech to text batch API and check the status of the transcription until it's done.
> - Inside the folder `src/processor` a skeleton of the orchestration file called `AudioTranscriptionOrchestration.cs` is provided to you.
> - Explore the `SpeechToTextService.cs` file and the `Transcription.cs` model provided to get the transcription.
> - Update the `StartTranscription`, `CheckTranscriptionStatus` and `GetTranscription` methods inside the `AudioTranscriptionOrchestration.cs` file

</div>

<details>
<summary> Toggle solution</summary>

The 3 methods `StartTranscription`, `CheckTranscriptionStatus` and `GetTranscription` are activity functions which represent the basic unit of work in a durable function orchestration. In our context Activity functions are the functions and tasks that are orchestrated in the process to communicate with the Speech To Text service.

The `StartTranscription` method will call the `SpeechToTextService` to be able to start the creation of a batch to run the transcription of an Audio file.

Update the `StartTranscription` method with this content:

```csharp
ILogger logger = executionContext.GetLogger(nameof(StartTranscription));
logger.LogInformation($"Starting transcription of {audioFile.Id}");

var jobUri = await SpeechToTextService.CreateBatchTranscription(audioFile.UrlWithSasToken, audioFile.Id);

logger.LogInformation($"Job uri for {audioFile.Id}: {jobUri}");

return jobUri;
```

By starting the creation of a batch transcription using the `SpeechToTextService` you will receive a job URI for this transcription. This job URI will be used to check the status of the transcription and get the transcription itself.

Then you will need to update the `CheckTranscriptionStatus` function with this code:

```csharp
ILogger logger = executionContext.GetLogger(nameof(CheckTranscriptionStatus));
logger.LogInformation($"Checking the transcription status of {audioFile.Id}");
var status = await SpeechToTextService.CheckBatchTranscriptionStatus(audioFile.JobUri!);
return status;
```

This function will check the status of the transcription using the `SpeechToTextService` and return the status.

Finally, you will need to implement the `GetTranscription` function:

```csharp
ILogger logger = executionContext.GetLogger(nameof(GetTranscription));
var transcription = await SpeechToTextService.GetTranscription(audioFile.JobUri!);
logger.LogInformation($"Transcription of {audioFile.Id}: {transcription}");
return transcription;
```

This function will get the transcription of the audio file using the `SpeechToTextService` and return the transcription.

As you probably noticed, each function use his own logger to log the different steps of the orchestration. This will help you to debug the orchestration if needed.

Each of those functions (`StartTranscription`, `CheckTranscriptionStatus` and `GetTranscription`) are called in the orchestration method `RunOrchestrator`.

</details>

## Deploy to Azure

You can now deploy your `processor` function and upload an audio file to see if the transcription is correctly running and check the logs of your Azure Function to see the different steps of the orchestration running. 

```sh
azd deploy processor
```

## Test the scenario

By now you should have a solution that invoke the execution of an Azure Durable Function responsible for retrieving the audio transcription thanks to a Speech to Text (Cognitive Service) batch processing call. You can try to delete and upload once again the audio file in the storage `audios` container of your Storage Account. You will see the different Activity Functions be called in the Azure Functions logs.

After a few minutes, you should see the transcription of the audio file in the logs of the Azure Function:

For the `StartTranscription` Activity Function:

![Start Transcription activity function](assets/func-start-transcription.png)

For the `CheckTranscriptionStatus` Activity Function:

![Check Transcription activity function](assets/func-check-transcription.png)

As you can see, multiple calls are made to the `CheckTranscriptionStatus` Activity Function to check the status of the transcription.

For the `GetTranscription` Activity Function:

![Get Transcription activity function](assets/func-get-transcription.png)


## Lab 2 : Summary

You have now a connection setup between your Azure Durable Function and the Speech to Text service to do the transcription of the audio files.

---

# Lab 3 : Use Azure Functions with Azure OpenAI

In this lab you will use Azure Functions to call the Azure OpenAI service to analyze the transcription of the audio file and add some information to the Cosmos DB entry.

You will go back to the Azure Durable Function you did in the previous lab and add a connection to Azure OpenAI to be able to summarize the transcription you saved.

So the scope of the lab is this one:

![Hand's On Lab Architecture Lab](assets/azure-functions-lab3.png)

## Enrich the transcription with Azure OpenAI

<div class="task" data-title="Tasks">

> - Update the Activity function `EnrichTranscription` inside the `AudioTranscriptionOrchestration.cs` to call Azure OpenAI via `TextCompletionInput`
> - Define a prompt to ask the model to summarize the audio transcription 
> - Use the result to update the `Completion` field of the transcription.

</div>

<details>
<summary> Toggle solution</summary>

First, you need to add the `TextCompletionInput` binding to the `EnrichTranscription` method:

```csharp
[Function(nameof(EnrichTranscription))]
public static AudioTranscription EnrichTranscription(
    [ActivityTrigger] AudioTranscription audioTranscription, FunctionContext executionContext,
    [TextCompletionInput("Summarize {Result}", Model = "%CHAT_MODEL_DEPLOYMENT_NAME%")] TextCompletionResponse response
)
```

The `TextCompletionInput` binding is defining a prompt to ask the model to summarize the audio transcription. It will use the `CHAT_MODEL_DEPLOYMENT_NAME` environment variable to get the model name to use.

This will manage for you the authentication to the Azure OpenAI service and send the transcription to the service to get a summary of the transcription.

Then you just have to consume the `Content` property of the response object and update the `Completion` field of the `AudioTranscription` object:

```csharp
audioTranscription.Completion = response.Content;
```

And that's it, you have now enriched the transcription of the audio file with the Azure OpenAI service!

So, to summarize, the function will look like this:

```csharp
[Function(nameof(EnrichTranscription))]
public static AudioTranscription EnrichTranscription(
    [ActivityTrigger] AudioTranscription audioTranscription, FunctionContext executionContext,
    [TextCompletionInput("Summarize {Result}", Model = "%CHAT_MODEL_DEPLOYMENT_NAME%")] TextCompletionResponse response
)
{
    ILogger logger = executionContext.GetLogger(nameof(EnrichTranscription));
    logger.LogInformation($"Enriching transcription {audioTranscription.Id}");
    audioTranscription.Completion = response.Content;
    return audioTranscription;
}
```

</details>

## Deploy to Azure

You can now redeploy your `processor` function and upload an audio file to see if the transcription is correctly running and check the logs of your Azure Function to see the different steps of the orchestration running. 

```sh
azd deploy processor
```

## Test the scenario

You can try to delete and upload once again the audio file in the storage `audios` container of your Storage Account. You will see the `EnrichTranscription` Activity Functions be called in the Azure Functions logs:

![Enrich Transcription activity function](assets/func-enrich-transcription.png)

You can play with the prompt of the `TextCompletionInput` if you wan't to have a more specific task based on the transcription.

## Lab 3 : Summary

By now you should have a solution that invoke Azure OpenAI to create a summary of the transcription.

---

# Lab 4 : Use Azure Functions with Cosmos DB

## Store data to Cosmos DB

In this lab, you will focus on the following scope :

![Hand's On Lab Architecture Lab](assets/azure-functions-lab4.png)

[Azure Cosmos DB][cosmos-db] is a fully managed NoSQL database which offers Geo-redundancy and multi-region write capabilities. It currently supports NoSQL, MongoDB, Cassandra, Gremlin, Table and PostgreSQL APIs and offers a serverless option which is perfect for our use case.

You now have a transcription of your audio file, next step is to store it in a NoSQL database inside Cosmos DB.

<div class="task" data-title="Tasks">

> - You will use the [CosmosDBOutput][cosmos-db-output-binding] binding to store the data in the Cosmos DB with a manage identity to connect to Cosmos DB.
> - Store the `AudioTranscription` object in the Cosmos DB container called `audios_transcripts`.
> - Update the activity Function called `SaveTranscription` to store the transcription of the audio file in Cosmos DB.

</div>

<details>
<summary> Toggle solution</summary>

To store the transcription of the audio file in Cosmos DB, you will need to update the `Activity Function` called `SaveTranscription` in the `AudioTranscriptionOrchestration.cs` file and apply the `CosmosDBOutput` binding to store the data in the Cosmos DB:

```csharp
[Function(nameof(SaveTranscription))]
[CosmosDBOutput("%COSMOS_DB_DATABASE_NAME%",
                    "%COSMOS_DB_CONTAINER_ID%",
                    Connection = "COSMOS_DB",
                    CreateIfNotExists = true)]
public static AudioTranscription SaveTranscription([ActivityTrigger] AudioTranscription audioTranscription, FunctionContext executionContext)
{
    ILogger logger = executionContext.GetLogger(nameof(SaveTranscription));
    logger.LogInformation("Saving the audio transcription...");

    return audioTranscription;
}
```

As you can see, by just defining the binding, the Azure Function will take care of storing the data in the Cosmos DB container, so you just need to return the object you want to store, in this case, the `AudioTranscription` object.

To be able to connect the Azure Function to the Cosmos DB, you have the `COSMOS_DB_DATABASE_NAME`, the `COSMOS_DB_CONTAINER_ID` and the `COSMOS_DB` environment variables. 

The `COSMOS_DB` value will be the connection key which will be concatenated with `__accountEndpoint` to specify the Cosmos DB account endpoint so it will be able to connect using Managed identity.

Those environment variables are already set in the Azure Function App settings (`func-drbl-<your-instance-name>`) when the infrastructure was deployed.

</details>

## Deploy to Azure

You can now redeploy your `processor` function and upload an audio file to see if the transcription is correctly running and check the logs of your Azure Function to see the different steps of the orchestration running. 

```sh
azd deploy processor
```

## Test the scenario

You can now validate the entire workflow : delete and upload once again the audio file. You will see the `SaveTranscription` Activity Functions be called in the Azure Functions logs:

![Save Transcription activity function](assets/func-save-transcription.png)

You should also see the new item created above in your Cosmos DB container with also a property called `completion` with a summary of the audio made by Azure OpenAI:

![Func Cosmos Summary Result](assets/func-cosmos-summary-result.png)

## Lab 4 : Summary

By now you should have a solution that:

- Invoke the execution of an Azure Durable Function responsible for retrieving the audio transcription thanks to a Speech to Text (Cognitive Service) batch processing call.
- Once the transcription is retrieved, the Azure Open AI model will enrich your transcript and the Azure Durable Function will store it in the Cosmos DB database. 

You have now a full scenario with your Azure Durable Function!

[cosmos-db-output-binding]: https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-cosmosdb-v2-output?tabs=python-v2%2Cisolated-process%2Cnodejs-v4%2Cextensionv4&pivots=programming-language-csharp
[cosmos-db]: https://learn.microsoft.com/en-us/azure/cosmos-db/introduction

---

# Appendix

## A bit of theory

### Azure Functions

Azure Functions is a `compute-on-demand` solution, offering a common function programming model for various languages. To use this serverless solution, no need to worry about deploying and maintaining infrastructures, Azure provides with the necessary up-to-date compute resources needed to keep your applications running. Focus on your code and let Azure Functions handle the rest.

Azure Functions are event-driven : They must be triggered by an event coming from a variety of sources. This model is based on a set of `triggers` and `bindings` which let you avoid hard-coding access to other services. 

In the same `Function App` you will be able to add multiple `functions`, each with its own set of triggers and bindings. These triggers and bindings can benefit from existing `expressions`, which are parameter conventions easing the overall development experience. For example, you can use an expression to use the execution timestamp, or generate a unique `GUID` name for a file uploaded to a storage account.

### Managed identities

Security is our first concern at Microsoft. To avoid any credential management issues, the best practice is to use managed identities on Azure. They offer several key benefits:

- **Enhanced Security**: Managed identities eliminate the need to store credentials in your code, reducing the risk of accidental leaks or breaches.
- **Simplified Credential Management**: Azure automatically handles the lifecycle of these identities, so you don’t need to manually manage secrets, passwords, or keys.
- **Seamless Integration**: Managed identities can authenticate to any Azure service that supports Microsoft Entra ID authentication, making it easier to connect and secure your applications.
- **Cost Efficiency**: There are no additional charges for using managed identities, making it a cost-effective solution for securing your Azure resources.

All the labs use managed identities.


## Testing locally

In this section you will focus on the following scope :

![Hand's On Lab Test Locally](assets/azure-functions-test-locally.png)

Let's run the first function inside the `src/uploader` folder. In the `AudioUpload.cs` you can discover how simple the code is to define an `HTTP Trigger` function to upload an audio file.

### Run the function locally

Create a new file called `local.settings.json` inside `src/uploader` folder and add the following environment variables:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "STORAGE_ACCOUNT_CONTAINER": "audios",
    "AudioUploadStorage": "UseDevelopmentStorage=true"
  }
}
```

To test your function locally, you will need to start the extension `Azurite` to emulate the Azure Storage Account. Just run `Ctrl` + `Shift` + `P` and search for `Azurite: Start`:

![Start Azurite](assets/function-azurite.png)

Then inside `src/uploader` folder you can use the Azure Function Core Tools to run the function locally:

```bash
func start
```

if you have an error such as:

> Can't determine Project to build. Expected 1 .csproj or .fsproj but found 2

Just remove the bin and obj folder and run the command again, the issue is currently being corrected.

```bash
rm -rf bin/ && rm -rf obj/ && func start
```

### Upload an audio file

Upload an audio file to Azurite's blob storage using the function running locally.

To do that you can use one of the sample audio files provided in the workshop:

- [Microsoft AI](assets/audios/MicrosoftAI.wav)
- [Azure Functions](assets/audios/AzureFunctions.wav)

Next, run the following command to upload the audio file. You can also use Postman or another HTTP client if you have previously opted for using a dev container or a local dev environment.

```sh
curl -v -F audio=@docs/assets/audios/MicrosoftAI.wav http://localhost:7071/api/AudioUpload
```

### Check blob creation

Finally, make sure that the audio file was saved in Azurite as a blob with the name `[GUID].wav`.

We will use the [Azure Storage extension][azure-storage-extension] to list available blobs in the `audios` container in Azurite (Local Emulator):

![Start Azurite](assets/azurite-explorer.png)

You can repeat the same test commands to ensure new files get saved in Azurite whenever you upload a file using the function running locally.


## Test the scenario

Let's give the new function a try using [Postman][postman]. Go to the Azure Function starting with `func-std-` and select `Functions` then `AudioUpload` and select the `Get Function Url` with the `default (function key)`.
The Azure Function url is protected by a code to ensure a basic security layer. 

![Azure Function url credentials](assets/func-url-credentials.png)

Use this url with Postman to upload the audio file.

You can use the provided sample audio files to test the function (click on the link and download the file):

- [Microsoft AI](assets/audios/MicrosoftAI.wav)
- [Azure Functions](assets/audios/AzureFunctions.wav)

Create a POST request and in the row where you set the key to `audio` for instance then, make sure to select the `file` option in the hidden dropdown menu to be able to select a file in the value field:

![Postman](assets/func-postman.png)

Go back to the Storage Account and check the `audios` container. You should see the files that you uploaded with your `AudioUpload` Azure Function!

---

# Closing the workshop

Once you're done with this lab you can delete the resource group you created at the beginning.

To do so, click on `delete resource group` in the Azure Portal to delete all the resources and audio content at once. The following Az-Cli command can also be used to delete the resource group :

```bash
# Delete the resource group with all the resources
az group delete --name <resource-group>
```