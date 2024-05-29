# Introduce external service in your datacenter with Consul ESM

This repository contains companion code for the following tutorial:

- [Introduce external service in your datacenter with Consul ESM](https://developer.hashicorp.com//consul/tutorials/connect-services/service-registration-external-services)

> **WARNING:** the script is currently under development. Some configurations might not work as expected. **Do not test on production environments.**

The code in this repository is derived from [hashicorp-education/learn-consul-get-started-vms](https://github.com/hashicorp-education/learn-consul-get-started-vms).


### Deploy

```
cd self-managed/infrastructure/aws
```

```
terraform apply --auto-approve -var-file=../../ops/conf/monitor_external_services_with_consul_esm.tfvars
```