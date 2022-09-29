local common = import 'common.libsonnet';

local defaults = {
  local defaults = self,
  name: 'browser',
  namespace: error 'must provide namespace',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  resources: {},
  ports: {
    http: 7984,
    metrics: 9980,
  },
  serviceMonitor: false,

  appConfig: {
    blobstore: common.blobstore,
    maximumMessageSizeBytes: common.maximumMessageSizeBytes,
    listenAddress: ':%d' % defaults.ports.http,
    global: common.globalWithDiagnosticsHttpServer(':9984'),
    authorizer: { allow: {} },
  },

  commonLabels:: {
    'app.kubernetes.io/name': 'browser',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/component': 'object-store-browser',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
  },
};

function(params) {
  local b = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: b.config.name,
      namespace: b.config.namespace,
      labels: b.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(b.config.ports[name]),

          name: name,
          port: b.config.ports[name],
          targetPort: b.config.ports[name],
        }
        for name in std.objectFields(b.config.ports)
      ],
      selector: b.config.podLabelSelector,
    },
  },

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: b.config.name,
      namespace: b.config.namespace,
      labels: b.config.commonLabels,
    },
    data: {
      'browser.jsonnet': b.config.appConfig,
    },
  },

  deployment:
    local c = {
      name: 'browser',
      image: b.config.image,
      args: ['/config/%s.jsonnet' % b.config.name],
      ports: [
        { name: port.name, containerPort: port.port }
        for port in b.service.spec.ports
      ],
      livenessProbe: {
        httpGet: {
          scheme: 'HTTP',
          // TODO(midnight): make this not rely on position
          port: b.config.ports.metrics,
          path: '/-/healthy',
        },
      },
      readinessProbe: {
        httpGet: {
          scheme: 'HTTP',
          // TODO(midnight): make this not rely on position
          port: b.config.ports.metrics,
          path: '/-/healthy',
        },
      },
      resources: if b.config.resources != {} then b.config.resources else {},
      volumeMounts: [{
        mountPath: '/config/',
        name: 'configs',
        readOnly: true,
      }],
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: b.config.name,
        namespace: b.config.namespace,
        labels: b.config.commonLabels,
      },
      spec: {
        replicas: b.config.replicas,
        selector: { matchLabels: b.config.podLabelSelector },
        template: {
          metadata: {
            labels: b.config.commonLabels,
          },
          spec: {
            containers: [c],
            // pefer to schedule one per kubernetes node
            affinity: { podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [{
                podAffinityTerm: {
                  namespaces: [b.config.namespace],
                  topologyKey: 'kubernetes.io/hostname',
                  labelSelector: { matchExpressions: [{
                    key: 'app.kubernetes.io/name',
                    operator: 'In',
                    values: [b.deployment.metadata.labels['app.kubernetes.io/name']],
                  }] },
                },
                weight: 100,
              }],
            } },
            volumes: [{
              name: 'configs',
              projected: {
                sources: [
                  {
                    configMap: {
                      name: '%s' % b.config.name,
                      items: [{
                        key: '%s.jsonnet' % b.config.name,
                        path: '%s.jsonnet' % b.config.name,
                      }],
                    },
                  },
                  {
                    configMap: {
                      name: 'common',
                      items: [{
                        key: 'common.jsonnet',
                        path: 'common.jsonnet',
                      }],
                    },
                  },
                ],
              },
            }],
          },
        },
      },
    },

  serviceMonitor: if b.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: b.config.name,
      namespace: b.config.namespace,
      labels: b.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: b.config.podLabelSelector,
      },
      endpoints: [{ port: 'http' }],
    },
  },
}
