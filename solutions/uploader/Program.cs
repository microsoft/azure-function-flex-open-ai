using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Azure;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices((hostContext, services) => {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        services.Configure<LoggerFilterOptions>(options =>
        {
            LoggerFilterRule toRemove = options.Rules.FirstOrDefault(rule => rule.ProviderName
                == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");

            if (toRemove is not null)
            {
                options.Rules.Remove(toRemove);
            }
        });
        services.AddAzureClients(clientBuilder => {
            clientBuilder.AddBlobServiceClient(hostContext.Configuration.GetSection("AudioUploadStorage")).WithName("audioUploader");
        });
    })
    .ConfigureAppConfiguration((hostContext, config) =>
    {
        config.AddJsonFile("host.json", optional: true);
    })
    .ConfigureLogging((hostingContext, logging) =>
    {
        logging.AddApplicationInsights(console =>
        {
            console.IncludeScopes = true;
        });
        logging.AddConfiguration(hostingContext.Configuration.GetSection("Logging"));
    })
    .Build();

host.Run();