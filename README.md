# kube-prometheus-blackbox-exporter

This is a [blackbox_exporter](https://github.com/prometheus/blackbox_exporter) library for [kube-prometheus](https://github.com/coreos/kube-prometheus) which provides bellow:

- Add [blackbox_exporter](https://github.com/prometheus/blackbox_exporter) deployment with [configmap-reload](https://github.com/jimmidyson/configmap-reload)
- Add additional scrape configs to prometheus-operator
- Add Service Monitor for blackbox_exporter deployed

## Install

Use this package in your own infrastructure using jsonnet-bundler:

```bash
jb install github.com/moguraion/kube-prometheus-blackbox-exporter
```

## Usage

### Use alone

Import this library and put some configuration you need. An example of how to use it alone bellow: (save as example.jsonnet)

```jsonnet
local kp =
  (import 'kube-prometheus-blackbox-exporter/kube-prometheus-blackbox-exporter.libsonnet') +
  {
    _config+:: {
      namespace: 'monitoring',
    },
    blackboxexporter+:: {
      config: {
        modules: {
          http_2xx: {
            http: {
              no_follow_redirects: false,
              preferred_ip_protocol: 'ip4',
              valid_http_versions: [
                'HTTP/1.1',
                'HTTP/2',
              ],
              valid_status_codes: [],
            },
            prober: 'http',
            timeout: '5s',
          },
        },
      },
    },
  };

{ ['blackbox-exporter-' + name]: kp.blackBoxExporter[name] for name in std.objectFields(kp.blackBoxExporter) }
```

and run:

```bash
jsonnet -J vendor example.jsonnet
```

### Use with kube-prometheus

An example of how to use with kube-prometheus bellow: (Edit in [example.jsonnet](https://github.com/coreos/kube-prometheus/blob/master/example.jsonnet) in [kube-prometheus](https://github.com/coreos/kube-prometheus))

```jsonnet
local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus-blackbox-exporter/kube-prometheus-blackbox-exporter.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-node-ports.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-thanos-sidecar.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-custom-metrics.libsonnet') +
  {
    _config+:: {
      namespace: 'monitoring',
    },
  };

{ ['setup/0namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor is separated so that it can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
{ ['blackbox-exporter-' + name]: kp.blackBoxExporter[name] for name in std.objectFields(kp.blackBoxExporter) }
```

## Configuration

This library extends kube-prometheus configuration field.
These are the available fields with their respective default values:

```jsonnet
{
  _config+:: {
    namespace: 'default',

    versions+:: {
      blackboxexporter: 'v0.15.1',
    },

    imageRepos+:: {
      blackboxexporter: 'prom/blackbox-exporter',
    },

    blackboxexporter+:: {
      name: 'blackbox-exporter',
      port: 9115,
      labels: {
        name: $._config.blackboxexporter.name,
      },
      config: {
        modules: {
          http_2xx: {
            http: {
              no_follow_redirects: false,
              preferred_ip_protocol: 'ip4',
              valid_http_versions: [
                'HTTP/1.1',
                'HTTP/2',
              ],
              valid_status_codes: [],
            },
            prober: 'http',
            timeout: '5s',
          },
        },
      },
      configmapReload+:: {
        version: 'v0.2.2',
        imageRepo: 'jimmidyson/configmap-reload',
      },
    },

    prometheus+:: {
      additionalScrapeConfig: {
        secretResourceName: 'additional-scrape-configs',
        dataKey: 'prometheus-additional.yaml',
        scrapeConfigs: [
        ],
      },
    },
  },
}
```

|key|description|
|:-|:-|
|blackboxexporter.config|Put configuraion for blackbox_exporter in JSON format. (See [doc](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md))|
|prometheus.additionalScrapeConfig.scrapeConfigs|Put scrape config for additional one. (For adding blackbox_exporter scraping configuration, see [doc#Prometheus Configuration](https://github.com/prometheus/blackbox_exporterhttps://github.com/prometheus/blackbox_exporter#prometheus-configuration)) Any custom prometheus scrape configuration is able to be putted here also.|
