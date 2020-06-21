local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';
local service = k.core.v1.service;
local deployment = k.apps.v1.deployment;
local coreContainer = (import 'ksonnet/ksonnet.beta.1/k.libsonnet').core.v1.container;

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
  blackBoxExporter: {
    configMap: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: $._config.blackboxexporter.name,
        labels: $._config.blackboxexporter.labels,
        namespace: $._config.namespace,
      },
      data: {
        'config.yaml': std.manifestYamlDoc($._config.blackboxexporter.config),
      },
    },

    service:
      service.new($._config.blackboxexporter.name, $._config.blackboxexporter.name, [{ name: 'http', port: $._config.blackboxexporter.port, protocol: 'TCP' }]) +
      service.mixin.metadata.withLabels($._config.blackboxexporter.labels) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.spec.withType('ClusterIP') +
      service.mixin.spec.withSelector($._config.blackboxexporter.labels),

    deployment:
      local container = deployment.mixin.spec.template.spec.containersType;
      local blackBoxExporterContainer =
        container.new($._config.blackboxexporter.name, $._config.imageRepos.blackboxexporter + ':' + $._config.versions.blackboxexporter) +
        container.withImagePullPolicy('IfNotPresent') +
        container.withArgs([
          '--config.file=/config/config.yaml',
        ]) +
        container.withPorts(container.portsType.newNamed($._config.blackboxexporter.port, 'http')) +
        {
          securityContext: {
            readOnlyRootFilesystem: true,
            runAsNonRoot: true,
            runAsUser: 1000,
          },
          resources: {},
          livenessProbe: {
            httpGet: {
              path: '/health',
              port: 'http',
            },
          },
          readinessProbe: {
            httpGet: {
              path: '/health',
              port: 'http',
            },
          },
          volumeMounts: [
            {
              mountPath: '/config',
              name: 'config',

            },
          ],
        };
      local configLoaderContainer =
        coreContainer.name('configmap-reload') +
        coreContainer.image($._config.blackboxexporter.configmapReload.imageRepo + ':' + $._config.blackboxexporter.configmapReload.version) +
        coreContainer.imagePullPolicy('IfNotPresent') +
        coreContainer.securityContext({
          runAsNonRoot: true,
          runAsUser: 65534,
        }) +
        coreContainer.args([
          '--volume-dir=/etc/config',
          '--webhook-url=http://localhost:%s/-/reload' % $._config.blackboxexporter.port,
        ]) +
        coreContainer.resources({}) +
        coreContainer.volumeMounts([
          {
            mountPath: '/etc/config',
            name: 'config',
            readOnly: true,
          },
        ]);

      deployment.new($._config.blackboxexporter.name, 1, [blackBoxExporterContainer, configLoaderContainer], $._config.blackboxexporter.labels) +
      deployment.mixin.metadata.withNamespace($._config.namespace) +
      deployment.mixin.metadata.withLabels($._config.blackboxexporter.labels) +
      deployment.mixin.spec.selector.withMatchLabels($._config.blackboxexporter.labels) +
      deployment.mixin.spec.template.spec.withVolumes([
        {
          name: 'config',
          configMap: {
            name: $._config.blackboxexporter.name,
          },
        },
      ]),

    serviceMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: $._config.blackboxexporter.name,
        namespace: $._config.namespace,
        labels: {
          prometheus: 'k8s',
        },
      },
      spec: {
        jobLabel: 'k8s-app',
        selector: {
          matchLabels: $._config.blackboxexporter.labels,
        },
        endpoints: [
          {
            port: 'http',
            honorLabels: true,
          },
        ],
      },
    },
  },
  prometheus+: {
    prometheus+: {
      spec+: {
        additionalScrapeConfigs+: {
          name: $._config.prometheus.additionalScrapeConfig.secretResourceName,
          key: $._config.prometheus.additionalScrapeConfig.dataKey,
        },
      },
    },
    additionalScrapeConfig:
      local secret = k.core.v1.secret;
      secret.new(
        $._config.prometheus.additionalScrapeConfig.secretResourceName,
        {
          [$._config.prometheus.additionalScrapeConfig.dataKey]: std.base64(std.toString(std.strReplace(std.manifestYamlDoc($._config.prometheus.additionalScrapeConfig.scrapeConfigs), '"', ''))),
        }
      ) +
      secret.mixin.metadata.withNamespace($._config.namespace) +
      { metadata+: { creationTimestamp: null } },
  },
}
