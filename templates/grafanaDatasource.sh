# Get prometheus URL and Grafana URL and token
# Note that we assume you settled the env MONITORING_NS with the value of the namespace where you are performing the installation
echo "target namespace is: $MONITORING_NS"
export PROMETHEUS_URL=https://$(oc get route prometheus  -n $MONITORING_NS | grep -v NAME | awk '{print $2}')
export    GRAFANA_URL=https://$(oc get route grafana-ocp -n $MONITORING_NS | grep -v NAME | awk '{print $2}')
export          TOKEN=$(oc sa get-token grafana-ocp -n $MONITORING_NS)

# Call the grafana /api/datasources to create the datasource
echo '
{
  "id": 1,
  "orgId": 1,
  "name": "prometheus",
  "type": "prometheus",
  "typeLogoUrl": "public/app/plugins/datasource/prometheus/img/prometheus_logo.svg",
  "access": "proxy",
  "url": "'$PROMETHEUS_URL'",
  "password": "",
  "user": "",
  "database": "",
  "basicAuth": false,
  "isDefault": true,
  "jsonData": {
    "tlsSkipVerify": true,
    "token": "'$TOKEN'"
  }
}
' | curl -k -d @- \
  --fail \
  --insecure \
  --request "POST" "$GRAFANA_URL/api/datasources" \
  --header "Content-Type: application/json" \
  --write-out '%{http_code}'
echo
