using System;
using System.Threading.Tasks;
using Confluent.Kafka;
using StackExchange.Redis;

class TemperatureProducer
{
    static async Task Main(string[] args)
    {
        var config = new ProducerConfig { BootstrapServers = "localhost:9092" };
        using var producer = new ProducerBuilder<Null, string>(config).Build();

        var redis = ConnectionMultiplexer.Connect("localhost:6379");
        var db = redis.GetDatabase();

        while (true)
        {
            var temperature = SimulateTemperature();
            Console.WriteLine($"Current temperature: {temperature}°C");

            // Store in Redis
            await db.StringSetAsync("greenhouse:temperature", temperature);

            // Produce to Kafka
            await producer.ProduceAsync("temperature-topic", new Message<Null, string> { Value = temperature.ToString() });

            await Task.Delay(5000); // Wait for 5 seconds before next reading
        }
    }

    static double SimulateTemperature()
    {
        // Simulate temperature between 20°C and 40°C
        return Math.Round(new Random().NextDouble() * 20 + 20, 1);
    }
}