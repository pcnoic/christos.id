---
title: Unit Testing Prometheus Rules for Reliable Monitoring
description: Unit test your Prometheus rules for peace of mind.
date: 2023-04-07
author: Christos Alexiou
tags:
  - monitoring
  - reliability
---

#### Table of Contents
- [Introduction](#introduction)
- [Unit Testing in Prometheus](#unit-testing-in-prometheus)
- [Setting Up Your Test Environment](#setting-up-your-test-environment)
- [Writing Unit Tests](#writing-unit-tests)
- [Case Study: An E-commerce Application](#case-study-an-e-commerce-application)
- [To Sum Up](#to-sum-up)

### Introduction

Systems tend to grow increasingly complex and interdependent, and reliability engineering must leverage the power of monitoring and observability tools to maintain applications. Among the myriad of available solutions, Prometheus has emerged as a powerful, open-source monitoring system, praised for its flexible query language and easy integration with other tools.

One of the core components of Prometheus is its rules system, which allows you to define alerting and recording rules. However, just like any other code, these rules can be prone to errors. To ensure the reliability of your monitoring setup, it's crucial to implement unit testing for your Prometheus rules. In this article, we will discuss how to set up a testing environment, write unit tests, and run them for your rules. We'll also explore a case study to see these concepts in action.

### Unit Testing in Prometheus

Prometheus provides a powerful built-in feature to test your rules using a YAML file, called the _Prometheus Unit Testing Framework_. This framework allows you to define a set of input series, the expected output, and assertions to validate your rules' correctness. Unit tests are an essential part of any software development process, and applying this practice to your Prometheus rules will help you prevent issues and improve overall reliability.

### Setting Up Your Test Environment

Before diving into writing unit tests, let's set up your test environment. First, you need to have Prometheus installed on your system. If you haven't done this yet, follow the [official guide](https://prometheus.io/docs/prometheus/latest/installation/) to get it up and running.

Next, create a directory structure to organize your rules and test files:

`mkdir -p prometheus/rules tests`

In the `prometheus/rules` directory, create a file named rules.yml to store your Prometheus rules. In the tests directory, create a file named `rules_test.yml` for the test scenarios.

### Writing Unit Tests

Now that your environment is ready, let's learn how to write unit tests. First, open the `rules_test.yml` file and start by defining a global evaluation time:

`evaluation_time: 2023-04-07T12:00:00Z`

Next, define the input series for your tests. This data simulates the time series that Prometheus would scrape from your application. Use the `input_series` key followed by a list of series with their respective labels and values:



```
input_series:
  - series: 'http_requests_total{job="app", instance="instance-1"}'
    values: '0 1 2 3 4 5 6 7 8 9'
```


Now it's time to write the test scenarios. Each scenario should be defined under the `tests` key. For each test, you should specify:

1. A unique name
2. An expression to be evaluated
3. The evaluation time for the expression (relative to the global evaluation time)
4. The expected output

Here's an example of a test scenario:



```
tests:
  - name: 'Test http_requests_total rate'
    expr: 'rate(http_requests_total{job="app", instance="instance-1"}[5m])'
    eval_time: 5m
    exp_result:
      - labels: 'instance=instance-1,job=app'
        value: '0.03333333333333333'
```



In this test, we're checking the rate of the `http_requests_total` metric for a specific job and instance over a 5-minute window. We expect the result to be `0.03333333333333333`.

With your test scenarios defined, it's time to run them. To do so, use the `promtool test rules` command followed by the path to your `rules_test.yml` file:

`promtool test rules tests/rules_test.yml`

If your tests pass, you'll see a success message. Otherwise, you'll get detailed information about the failed tests, helping you identify and fix issues in your rules.

### Case Study: An E-commerce Application

To demonstrate the power of unit testing Prometheus rules, let's consider a case study of an e-commerce application. The application consists of multiple services, such as authentication, payment processing, and inventory management.

We want to monitor the application's latency and error rate to ensure a smooth user experience. Here are two Prometheus rules defined in the `prometheus/rules/rules.yml` file:


```
groups:
  - name: example
    rules:
      - record: job:request_latency_seconds:mean_rate5m
        expr: rate(request_latency_seconds_sum{job="app"}[5m]) / rate(request_latency_seconds_count{job="app"}[5m])

      - alert: HighErrorRate
        expr: rate(http_requests_total{job="app", status_code=~"5.."}[5m]) / rate(http_requests_total{job="app"}[5m]) > 0.1
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "High error rate ("{{ '{{ $value }}' }}") detected for job "{{'{{ $labels.job }}'}}"
```


Now, let's create unit tests for these rules in the `tests/rules_test.yml` file:


```
evaluation_time: 2023-04-07T12:00:00Z

input_series:
  - series: 'request_latency_seconds_sum{job="app"}'
    values: '0 1 2 3 4 5 6 7 8 9'
  - series: 'request_latency_seconds_count{job="app"}'
    values: '1 1 1 1 1 1 1 1 1 1'
  - series: 'http_requests_total{job="app", status_code="200"}'
    values: '10 11 12 13 14 15 16 17 18 19'
  - series: 'http_requests_total{job="app", status_code="500"}'
    values: '0 1 2 3 4 5 6 7 8 9'

tests:
  - name: 'Test request_latency_seconds mean rate'
    expr: 'job:request_latency_seconds:mean_rate5m'
    eval_time: 5m
    exp_result:
      - labels: 'job=app'
        value: '1'

  - name: 'Test HighErrorRatealert'
    expr: 'ALERTS{alertname="HighErrorRate"}'
    eval_time: 5m
    exp_result:
      - labels: 'alertname=HighErrorRate,job=app,severity=critical'
        value: '1'

  - name: 'Test HighErrorRate alert not firing'
    expr: 'ALERTS{alertname="HighErrorRate"}'
    eval_time: 1m
    exp_result: []
```


In the test file, we define three tests. The first test validates the `request_latency_seconds` mean rate calculation. The second test checks if the `HighErrorRate` alert is firing when the error rate is above the threshold. The third test ensures the alert is not firing when the error rate is below the threshold.

Run the tests using the `promtool` command:

```bash
promtool test rules tests/rules_test.yml
```

If all tests pass, you can be confident that your rules are working correctly. Otherwise, you can adjust your rules and re-run the tests until they pass.

### To Sum Up

Unit testing your Prometheus rules is a crucial step to ensure the reliability of your monitoring setup. By leveraging the built-in Prometheus Unit Testing Framework, you can create a solid test suite that validates your alerting and recording rules, helping you identify and fix issues before they affect your production environment.

In this article, we covered how to set up a test environment, write unit tests, and run them using `promtool`. We also explored a case study of an e-commerce application to demonstrate the practical application of these concepts.

By incorporating unit testing into your Prometheus workflow, you'll be well on your way to creating a more robust and reliable monitoring system for your applications.
