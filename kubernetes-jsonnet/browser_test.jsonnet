local browser = import 'browser.libsonnet';

{
  assert std.isString(browser({ image: 'img' }).config.image) : 'image must be set',
  assert std.isString(browser({ namespace: 'ns' }).config.namespace) : 'namespace must be set',
  assert std.isNumber(browser({ replicas: 1 }).config.replicas) : 'replicas must be set',
}
