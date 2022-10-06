local frontend = import 'frontend.jsonnet';

local defaults = {
  local defaults = self,
  name: 'frontend',
  namespace: error 'must provide namespace',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  resources: {},
  ports: {
    grpc: 8980,
    metrics: 9980,
  },
  serviceMonitor: false,

  appConfig: frontend,

  commonLabels:: {
    'app.kubernetes.io/name': 'frontend',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/component': 'rpc-demultiplexing',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
  },
};

function(params) {
  local f = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: f.config.name,
      namespace: f.config.namespace,
      labels: f.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(f.config.ports[name]),

          name: name,
          port: f.config.ports[name],
          targetPort: f.config.ports[name],
        }
        for name in std.objectFields(f.config.ports)
      ],
      selector: f.config.podLabelSelector,
    },
  },

  commonConfigMap: (import 'common_configmap.libsonnet'),

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: f.config.name,
      namespace: f.config.namespace,
      labels: f.config.commonLabels,
    },
    data: {
      'frontend.jsonnet': f.config.appConfig,
    },
  },

  deployment:
    local c = {
      name: 'frontend',
      image: f.config.image,
      args: ['/config/%s.jsonnet' % f.config.name],
      ports: [
        { name: port.name, containerPort: port.port }
        for port in f.service.spec.ports
      ],
      livenessProbe: {
        httpGet: {
          scheme: 'HTTP',
          port: f.config.ports.metrics,
          path: '/-/healthy',
        },
      },
      readinessProbe: {
        httpGet: {
          scheme: 'HTTP',
          port: f.config.ports.metrics,
          path: '/-/healthy',
        },
      },
      resources: if f.config.resources != {} then f.config.resources else {},
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
        name: f.config.name,
        namespace: f.config.namespace,
        labels: f.config.commonLabels,
      },
      spec: {
        replicas: f.config.replicas,
        selector: { matchLabels: f.config.podLabelSelector },
        template: {
          metadata: {
            labels: f.config.commonLabels,
          },
          spec: {
            containers: [c],
            // pefer to schedule one per kubernetes node
            affinity: { podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [{
                podAffinityTerm: {
                  namespaces: [f.config.namespace],
                  topologyKey: 'kubernetes.io/hostname',
                  labelSelector: { matchExpressions: [{
                    key: 'app.kubernetes.io/name',
                    operator: 'In',
                    values: [f.deployment.metadata.labels['app.kubernetes.io/name']],
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
                      name: '%s' % f.config.name,
                      items: [{
                        key: '%s.jsonnet' % f.config.name,
                        path: '%s.jsonnet' % f.config.name,
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

  serviceMonitor: if f.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: f.config.name,
      namespace: f.config.namespace,
      labels: f.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: f.config.podLabelSelector,
      },
      endpoints: [{ port: 'http' }],
    },
  },
}
