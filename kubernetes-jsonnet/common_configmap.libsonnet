local common = import 'common.libsonnet';

local defaults = {
  local defaults = self,
  name: 'common',
  namespace: error 'must provide namespace',

  commonLabels:: {
    'app.kubernetes.io/name': 'common',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/component': 'common-configuration',
  },
};

function(params) {
  local c = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: c.config.name,
      namespace: c.config.namespace,
      labels: c.config.commonLabels,
    },
    data: { 'common.libsonnet': common },
  },
}
