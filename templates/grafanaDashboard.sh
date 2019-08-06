# Get grafana URL and dashboard json
# Note that we assume you settled 
#  - env MONITORING_NS with the value of the namespace where you are performing the installation
#  - env $MONITORING_BASEREPO with the value of content repo
#  - env $MONITORING_BRANCH with the value of the repo branch
export GRAFANA_URL=https://$(oc get route grafana-ocp -n $MONITORING_NS | grep -v NAME | awk '{print $2}')
export DASHBOARD=$(curl --insecure $MONITORING_BASEREPO/$MONITORING_BRANCH/templates/grafanaDashboard.json)

# Call the grafana /api/dashboards/import to create the datasource
echo $DASHBOARD | \
  curl -k -d @- \
    --fail \
    --insecure \
    --request "POST" "$GRAFANA_URL/api/dashboards/import" \
    --header "Content-Type: application/json" \
    --write-out '%{http_code}' && \
echo
