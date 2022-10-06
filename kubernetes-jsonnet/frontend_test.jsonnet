local frontend = import 'frontend.libsonnet';

{
  assert std.isString(frontend({ image: 'img' }).config.image) : 'image must be set',
  assert std.isString(frontend({ namespace: 'ns' }).config.namespace) : 'namespace must be set',
  assert std.isNumber(frontend({ replicas: 1 }).config.replicas) : 'replicas must be set',
}
