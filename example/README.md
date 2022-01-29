# Example

This is an example of using the github.com/dio/authservicebinary/api package.

```console
go run main.go --external-auth-service-config path/to/config.json
```

## Config

Please refer to [authservice/docs](../authservice/docs/README.md) to author a valid configuration for the `auth_server`.

The [config.json](./config.json) used in this example is taken from https://github.com/dio/authservice/blob/3f884b8d37b0d754751182fd8b67453f3cf0f4b0/bookinfo-example/config/authservice-configmap-template-for-authn.yaml#L14-L48.
