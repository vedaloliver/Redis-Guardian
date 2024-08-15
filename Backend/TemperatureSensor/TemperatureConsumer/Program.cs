using System;
using System.Threading;
using System.Threading.Tasks;
using Confluent.Kafka;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

class Program
{
    static void Main(string[] args)
    {
        var config = new ConsumerConfig
        {
            BootstrapServers = "localhost:9092",
            GroupId = "temperature-group",
            AutoOffsetReset = AutoOffsetReset.Earliest
        };

        var emailConfig = new SmtpConfig
        {
            Host = "smtp.gmail.com",
            Port = 587,
            Username = "ojward1995@gmail.com",
            Password = "your-app-password"
        };

        using var consumer = new ConsumerBuilder<Ignore, string>(config).Build();
        consumer.Subscribe("temperature-topic");

        CancellationTokenSource cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => {
            e.Cancel = true;
            cts.Cancel();
        };

        try
        {
            while (true)
            {
                var consumeResult = consumer.Consume(cts.Token);
                var temperature = double.Parse(consumeResult.Message.Value);
                Console.WriteLine($"Received temperature: {temperature}°C");

                if (temperature > 35)
                {
                    Console.WriteLine("Temperature exceeded 35°C! Sending alert email...");
                    //SendAlertEmail(emailConfig, temperature).Wait();
                }
            }
        }
        catch (OperationCanceledException)
        {
            consumer.Close();
        }
    }

    static async Task SendAlertEmail(SmtpConfig config, double temperature)
    {
        var message = new MimeMessage();
        message.From.Add(new MailboxAddress("Greenhouse Monitor", config.Username));
        message.To.Add(new MailboxAddress("Greenhouse Owner", "ojward1995@gmail.com"));
        message.Subject = "High Temperature Alert";
        message.Body = new TextPart("plain")
        {
            Text = $"The greenhouse temperature has reached {temperature}°C, which is above the threshold of 35°C."
        };

        using var client = new SmtpClient();
        await client.ConnectAsync(config.Host, config.Port, SecureSocketOptions.StartTls);
        await client.AuthenticateAsync(config.Username, config.Password);
        await client.SendAsync(message);
        await client.DisconnectAsync(true);
    }
}

class SmtpConfig
{
    public string Host { get; set; }
    public int Port { get; set; }
    public string Username { get; set; }
    public string Password { get; set; }
}