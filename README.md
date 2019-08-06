

# INTRO
This guide helps to setup a stack composed of:
* Prometheus
* Alert manager
* Grafana
* Kafka exporter
* A spring boot demo app
* A kafka infra for demo

Here you can see how components interact toghether

![components sequence diagram](https://raw.githubusercontent.com/p-sforza/springboot-monitoring-example/master/extras/diagram.png)

The document is organized as a demo script  and demo components can be usefull if you want use them to test your environemt or you can just jump some steps (marked with the note @demo ) if you want to setup the monitoring stack only. 


# REQUIREMENTS
* a bash shell (we recomend to use the bastion host of your cluster)
* oc client
* an OpenShift user with cluster-admin roles
# ENVIRONMENT SETUP
Set the values of these envs to personilize your deployment 
```
# [@demo] namespace where reside an app to be monitored 
export DEMO_APP='demo-monitored-app'

# [@demo] namespace where reside a kafka to be monitored
export DEMO_KAFKA='demo-monitored-kafka'

# namespace where to deploy the monitoring stack
export MONITORING_NS='monitoring-global'

# repo/branch of the code
export MONITORING_BASEREPO='https://raw.githubusercontent.com/p-sforza/springboot-monitoring-example'
export MONITORING_BRANCH='master'
```
# DEPLOY THE MONITORED APP
**[@demo]**
To deploy a demo app to scrape metrics from:
```
oc new-project $DEMO_APP
oc new-app -f $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/demoApp.yaml -n $DEMO_APP
```

**WARNING**
 If you are going to use your own app, **you have to tag objects to be scraped** (the demo app comes already configured for this). 
 
Here you are a snippet to tag PODs using a deploymetConfig...
```
...
  template:
    metadata:
      annotations:
        prometheus.io/path: /metrics
        prometheus.io/port: '9308'
        prometheus.io/scheme: http
        prometheus.io/scrape: 'true'
...
```
 … or a service
```
...
- apiVersion: v1
  kind: Service
  metadata:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/scheme: http
      prometheus.io/port: "8080"
    labels:
      app: ${APP_NAME}
...
```
**Note:** scraped path can be customized adding the annotation: 
```
...
      prometheus.io/path: /metrics
...
```
# DEPLOY PROMETHEUS

Create the project to host the monitoring stack and deploy Prometheus and the alert-manager components:
```
oc new-project $MONITORING_NS ; 

# Note: this allow the $MONITORING_NS to be reached by any POD into other naspaces but can generate error if multi-tenant plugin is not installed
oc adm pod-network make-projects-global $MONITORING_NS ;

oc new-app -f $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/prometheusTemplate.yaml -p NAMESPACE=$MONITORING_NS
```
**[@demo]**
... finally configure the scraping:

>**Note:** repeat this for every name space you want to add to prometheus scraping 
```
oc policy add-role-to-user view system:serviceaccount:$MONITORING_NS:prometheus -n $DEMO_APP

# Here you ave to configure prometheus jobs defining objects and re-labeling policy
# Note that in case of different object to be scraped you have to configure new jobs 
oc edit cm prometheus

...
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names:
      - <YOUR $DEMO_APP VALUE>
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
...

# Restart prometheus to reload config-map
#  Note: if the curl doesn't get effects, just delete or redeploy the pod:
#    oc delete pod prometheus-0 -n $MONITORING_NS
oc exec prometheus-0 -c prometheus -n $MONITORING_NS -- curl -X POST http://localhost:9090/-/reload 
```
# DEPLOY GRAFANA
Setup grafana, datasource to prometheus and a demo dashboard:
```
oc new-app -f $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/grafanaTemplate.yaml -p NAMESPACE=$MONITORING_NS

oc policy add-role-to-user view system:serviceaccount:$MONITORING_NS:grafana-ocp -n $MONITORING_NS

# the datasource for prometheus...
curl  $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/grafanaDatasource.sh | bash
```
**[@demo]**
```
# the dashboard for the demo app...
curl $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/grafanaDashboard.sh | bash

# to test the stack, perform some call to the demo app and you will be able to see data on the custom grafana dasboard
for i in {0..1000}; do curl -s  http://$(oc get route restservice -n demo-monitored-app | grep -v NAME | awk '{print $2}')/hello-world; done
```

# DEPLOY KAFKA EXPORTER
Setup the [kafka-exporter](https://github.com/danielqsj/kafka_exporter) components:

```
oc project $MONITORING_NS
oc new-app --docker-image=danielqsj/kafka-exporter:latest
```
>**Note:** As in following @demo example, if you have your own kafka infrastructure, remember to: 
>* configure the **kafka-exporter DeploymentConfig** to adjust **exporter start up broker list** and **tags for prometheus scraping**
>* **instrument prometheus** to look into kafka-exporter namespace
>* **instrument grafana** to render some metrics

**[@demo]**
Setup a kafka infrastructure (such as [strimzi](https://strimzi.io/quickstarts/okd/)):

>**Note:** in this demo, zookeper require a volume of 100gb and other 100gb are required by kafka broker
```
oc new-project $DEMO_KAFKA
oc apply -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.13.0/strimzi-cluster-operator-0.13.0.yaml -n $DEMO_KAFKA
oc apply -f https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/0.13.0/examples/kafka/kafka-persistent-single.yaml -n $DEMO_KAFKA

# Note that has to be tuned just in case of RBAC issues on strimzy operator:
#   oc adm policy add-role-to-user cluster-admin system:serviceaccount:$DEMO_KAFKA:strimzi-cluster-operator

# Edit the deployment config to configure kafka brokers...
oc edit dc kafka-exporter -n $MONITORING_NS
...
    spec:
      containers:
        - args:
            - >-
              --kafka.server=my-cluster-kafka-brokers.myproject.svc.cluster.local:9092
          image: >-
            danielqsj/kafka-exporter
...

# Then add scrapings lables to the kafka-exporter...
oc edit dc kafka-exporter -n $MONITORING_NS
...
  metadata:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/scheme: http
      prometheus.io/port: "9308"
...

# Then instrument prometheus... 
oc edit cm prometheus -n $MONITORING_NS
...
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names:
      - <YOUR $MONITORING_NS VALUE>
....

# Then instrument grafana adding some dashboard...

```


# CLEAN ALL
```
# Clean environment from monitoring stack
oc delete clusterrole prometheus-scraper 
oc delete clusterrolebindings prometheus-cluster-reader prometheus-scraper prometheus-cluster-reader
oc delete project $MONITORING_NS

# Clean environment from the demo app
oc delete project $DEMO_APP

# Clean environment from the kafka demo
oc delete project $DEMO_KAFKA

```
# TO-DO

 - [ ] Fix
	 - [ ] grafana punta alla rotta esterna di prometheus (originariamente erano su NS separati)
	 - [ ] upgrade di grafana e prometheus scassano le dashboard della demo app
 - [ ] separare demo app dal repo-root
 - [ ] update immagini 
	 - [ ] alertmanager latest richiede  arg --config (doppio - )
	 - [ ] grafana: mrsiano/openshift-grafana:5.2.0 
	 - [ ] Includere versioni immagini
 - [x] automazione config grafana
 - [ ] automazione config prometheus
  - [x] mark demo steps (@demo) 
 - [x] add code comments
 - [ ] kafka exporter
	 - [x] Deploy stack
	 - [ ] Include example of grafana dashboard for kafka
 - [ ] PVC Prometheus
 - [ ] Reintroduzione limiti
 - [ ] Automazione config prom auto
 - [ ] Export dashboard.json in configmap
 - [ ] PVC Grafana
 - [ ] template
 - [ ] operator
 - [ ] Remove strimzi volumes
