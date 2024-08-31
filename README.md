# EDA Playground

To have an unattended installation of EDA Playground, run the following command that will install a KinD cluster, EDA itself and a set of applications for you to play with.

```shell
make try-eda
```

Or if you want to install separate components of this playground, you can run the following commands in order:

```shell
make download-tools
make download-pkgs
make update-pkgs
make kind
make install-external-packages
make eda-configure-core
make eda-install-core
make eda-is-core-ready
make eda-install-apps
make eda-bootstrap
make topology-load
make start-ui-port-forward
```

## Make options for eda-configure-core

|   Make option   | Description                                                                                                                  |
| :-------------: | ---------------------------------------------------------------------------------------------------------------------------- |
| EXT_DOMAIN_NAME | The hostname/A/AAAA record that clients use to reach the cluster                                                             |
|  EXT_HTTP_PORT  | The external port that clients use to reach the cluster which directs to eda-api-service                                     |
| EXT_HTTPS_PORT  | The external port that clients use to reach the cluster which directs to eda-api-service                                     |
|  EXT_IPV4_ADDR  | Ideally the IP that EXT_DOMAIN_NAME points to                                                                                |
|  EXT_IPV6_ADDR  | Ideally the IP that EXT_DOMAIN_NAME points to                                                                                |
|   HTTPS_PROXY   | Is the cluster behind a proxy ? - your proxy url/ip                                                                          |
|   HTTP_PROXY    | Is the cluster behind a proxy ? - your proxy url/ip                                                                          |
|    NO_PROXY     | Is the cluster behind a proxy ? - remember to add internal coredns names + git servers : .local,.svc,eda-git,eda-git-replica |
|   https_proxy   | Is the cluster behind a proxy ? - your proxy url/ip                                                                          |
|   http_proxy    | Is the cluster behind a proxy ? - your proxy url/ip                                                                          |
|    no_proxy     | Is the cluster behind a proxy ? - remember to add internal coredns names + git servers : .local,.svc,eda-git,eda-git-replica |
|   LLM_API_KEY   | API key for the Natural query language                                                                                       |

## Make options for topology-load

| Make option | Description                                                   |
| :---------- | :------------------------------------------------------------ |
| TOPO        | Path to a topology file for api-topo to load into the cluster |

## Make options for eda-install-apps

| Make option                     | Description                                        |
| :------------------------------ | :------------------------------------------------- |
| NUMBER_OF_PARALLEL_APP_INSTALLS | Number of apps to install parallel - default is 20 |
