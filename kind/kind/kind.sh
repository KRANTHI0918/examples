#!/usr/bin/env bash
#
# 	Copyright (c) 2022 Avesha, Inc. All rights reserved. # # SPDX-License-Identifier: Apache-2.0
#
# 	Licensed under the Apache License, Version 2.0 (the "License");
# 	you may not use this file except in compliance with the License.
# 	You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" BASIS,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#	See the License for the specific language governing permissions and
#	limitations under the License.

start_time=`date +%M`

ENV=kind.env
CLEAN=false
VERBOSE=false

# Check if running in Linux or Mac
if [ "$(uname)" == "Linux" ]; then
    # First, check args
    VALID_ARGS=$(getopt -o chve: --long clean,help,verbose,env: -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    eval set -- "$VALID_ARGS"
    while [ : ]; do
      case "$1" in
        -e | --env)
            echo "Passed environment file is: '$2'"
    	ENV=$2
            shift 2
            ;;
        -c | --clean)
            CLEAN=true
            shift
            ;;
        -h | --help)
    	echo "Usage is:"
    	echo "    bash kind-ent.sh [<options>]"
    	echo " "
    	echo "    -c | --clean: delete all clusters"
    	echo "    -e | --env <environment file>: Specify custom environment details"
    	echo "    -h | --help: Print this message"
            shift
    	exit 0
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        --) shift; 
            break 
            ;;
      esac
    done
elif [ "$(uname)" == "Darwin" ]; then
    # First, check args
    while getopts "eenvccleanhhelpvverbose--" opt; do
    case "$opt" in
        e | env)
        if [[ $2 == '' ]]; then
            exit 1;
        fi
        echo "Passed environment file is: '$2'"
        ENV=$2
        shift 2
        ;;
        c | clean)
        CLEAN=true
        shift
        ;;
        h | help)
        echo "Usage is:"
        echo "    bash kind-ent.sh [<options>]"
        echo " "
        echo "    -c | --clean: delete all clusters"
        echo "    -e | --env <environment file>: Specify custom environment details"
        echo "    -h | --help: Print this message"
        shift
        exit 0
        ;;
        v | verbose)
        VERBOSE=true
        shift
        ;;
        --) shift;
        break
        ;;
    esac
    done

    if [[ ( $@ -ne '' )]]; then
        exit 1;
    fi
fi

# Pull in the specified environemnt
source $ENV

# Setup kind multicluster with KubeSlice
CONTROLLER_TEMPLATE="controller.template.yaml"
WORKER_TEMPLATE="worker.template.yaml"
SLICE_TEMPLATE="slice.template.yaml"
REGISTRATION_TEMPLATE="clusters-registration.template.yaml"

CLUSTERS=($CONTROLLER)
CLUSTERS+=(${WORKERS[*]})

clean() {
    echo Cleaning up all clusters
    for CLUSTER in ${CLUSTERS[@]}; do
        echo kind delete cluster --name $CLUSTER
        kind delete cluster --name $CLUSTER
    done
}

# Check for requirements
echo Checking for required tools...
ERR=0
which kind > /dev/null
if [ $? -ne 0 ]; then
    echo Error: kind is required and was not found
    ERR=$((ERR+1))
fi
which kubectl > /dev/null
if [ $? -ne 0 ]; then
    echo Error: kubectl is required and was not found
    ERR=$((ERR+1))
fi
which kubectx > /dev/null
if [ $? -ne 0 ]; then
    echo Error: kubectx is required and was not found
    ERR=$((ERR+1))
fi
which helm > /dev/null
if [ $? -ne 0 ]; then
    echo Error: helm is required and was not found
    ERR=$((ERR+1))
fi
which docker > /dev/null
if [ $? -ne 0 ]; then
    echo Error: docker is required and was not found
    ERR=$((ERR+1))
fi
# See if we're being asked to cleanup
if [ "$CLEAN" == true ]; then
    clean
    exit 0
fi

if [[ -z "$DOCKER_USER" ]] ; then echo "\$DOCKER_USER Variable is null" ; ERR=$((ERR+1)) ; fi
if [[ -z "$DOCKER_PASS" ]] ; then echo "\$DOCKER_PASS Variable is null" ; ERR=$((ERR+1)) ; fi
if [[ -z "$DOCKER_EMAIL" ]] ; then echo "\$DOCKER_EMAIL Variable is null" ; ERR=$((ERR+1)) ; fi
if [[ -z "$HELM_USER" ]] ; then echo "\$HELM_USER Variable is null" ; ERR=$((ERR+1)) ; fi
if [[ -z "$HELM_PASS" ]] ; then echo "\$HELM_PASS Variable is null" ; ERR=$((ERR+1)) ; fi

if [ $ERR -ne 0 ]; then
    echo Exiting due to Variables are null
    exit 0        # Done until all Variables are set
fi

TOKEN=$(curl "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)

# Check if running in Linux or Mac
if [ "$(uname)" == "Linux" ]; then
    # Increase the inotify.max_user_instances and inotify.max_user_watches sysctls under GNU/Linux platform
    INOT_USER_WAT=`sysctl fs.inotify.max_user_watches | awk '{ print $3 }'`
    if [ $INOT_USER_WAT -lt 524288 ]; then
	    echo Warning: kind recommends at least 524288 fs.inotify.max_user_watches
        echo Increase the inotify.max_user_watches sysctls on a Linux host with below command
        echo sudo sysctl fs.inotify.max_user_watches=524288
        echo sudo sysctl -p
    fi
    INOT_USER_INST=`sysctl fs.inotify.max_user_instances | awk '{ print $3 }'`
    if [ $INOT_USER_INST -lt 512 ]; then
	    echo Warning: kind recommends at least 512 fs.inotify.max_user_instances
        echo Increase the inotify.max_user_instances sysctls on a Linux host with below command
        echo sudo sysctl fs.inotify.max_user_instances=8192
        echo sudo sysctl -p
    fi

    RateLimit=$(echo $(curl --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1 | grep -i RateLimit) | cut -c 29-54 | cut -c 2-23 --complement)

    BSDSED=""

elif [ "$(uname)" == "Darwin" ]; then
    # Install colima under Mac OS X platform
    which colima > /dev/null
    if [ $? -ne 0 ]; then
        echo Error: colima is required and was not found
        echo Install colima with command "'brew install colima'" and
        echo Run command "'colima start --cpu 4 --memory 8'"
        echo To create VM with 4CPU, 8GiB memory and 10GiB storage
        ERR=$((ERR+1))
    fi
    which sed > /dev/null
    if [ $? -ne 0 ]; then
        echo Error: gnu-sed is required and was not found
        echo Install gnu-sed with command "'brew install gnu-sed'" and
        echo Run commands "'brew info gnu-sed'"
        ERR=$((ERR+1))
    fi
    command -v gcut > /dev/null
    if [ $? -ne 0 ]; then
        echo Error: coreutils is required and was not found
        echo Install coreutils with command "'brew install coreutils'"
        ERR=$((ERR+1))
    fi

    RateLimit=$(echo $(curl --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1 | grep -i RateLimit) | gcut -c 29-54 | gcut -c 2-23 --complement)
    
    BSDSED="''"

else
    # Not Ubuntu & Mac... on your own
    echo Environment is $(uname) \(not Ubuntu & Mac\)... other checks skipped
fi

RateLimit=`echo $RateLimit | sed 's/ *$//g' | sed 's/;*$//g'`
echo $RateLimit pull rate limit are remaining
if [ $RateLimit -le 48 ]; then
    echo "You have reached your pull rate limit. You may increase the limit by authenticating and upgrading: https://www.docker.com/increase-rate-limits. You must authenticate your pull requests."
    ERR=$((ERR+1))
fi

if [ $ERR -ne 0 ]; then
    echo Exiting due to missing required tools
    exit 0        # Done until all requirements are met
else
    echo Requirement checking passed
fi

# Create kind clusters
echo Create the Controller cluster
echo kind create cluster --name $CONTROLLER --config controller-cluster.yaml $KIND_K8S_VERSION
kind create cluster --name $CONTROLLER --config controller-cluster.yaml $KIND_K8S_VERSION

echo Create the Worker clusters
for CLUSTER in ${WORKERS[@]}; do
    echo Creating cluster $CLUSTER
    echo kind create cluster --name $CLUSTER --config worker-cluster.yaml $KIND_K8S_VERSION
    kind create cluster --name $CLUSTER --config worker-cluster.yaml $KIND_K8S_VERSION
    # Make sure the cluster context exists
    kubectl cluster-info --context $PREFIX$CLUSTER
done

# See if we're being asked to be chatty
if [ "$VERBOSE" == true ]; then
    # Log all the commands (w/o having to echo them)
    set -o xtrace
fi

function wait_for_pods {
  for ns in "$namespace"; do
    for pod in $(kubectl get pods -n $ns | grep -v NAME | awk '{ print $1 }'); do
      counter=0
      echo kubectl get pod $pod -n $ns
      kubectl get pod $pod -n $ns
      while [[ $(kubectl get po $pod | grep $pod | awk '{print $3}' -n $ns) =~ ^Running$|^Completed$ ]]; do
        sleep 1
        let counter=counter+1

        if ((counter == $sleep)); then
          echo "POD $pod failed to start in $sleep seconds"
          kubectl get events -n $ns --sort-by='.lastTimestamp'
          echo "Exiting"

          exit -1
        fi
      done
    done
  done
}

# Install Calico in Controller...
echo Switch to controller context and Install Calico...
kubectx $PREFIX$CONTROLLER
kubectx

echo Install the Tigera Calico operator...
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml

echo Install the custom resource definitions manifest...
kubectl create -f https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
sleep 120

echo "Check for Calico namespaces, pods"
kubectl get ns
kubectl get pods -n calico-system
echo "Wait for Calico to be Running"
namespace=calico-system
sleep=900
wait_for_pods

kubectl get pods -n calico-system

# Install Calico in Worker...
for WORKER in ${WORKERS[@]}; do

    # Install Calico in Worker...
    echo Switch to worker context and Install Calico...
    kubectx $PREFIX$WORKER
    kubectx

    echo Install the Tigera Calico operator...
    kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml

    echo Install the custom resource definitions manifest...
    kubectl create -f https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
    sleep 120

    echo "Check for Calico namespaces, pods"
    kubectl get ns
    kubectl get pods -n calico-system
    echo "Wait for Calico to be Running"
    namespace=calico-system
    sleep=900
    wait_for_pods

    kubectl get pods -n calico-system

done

# Helm repo access
echo Setting up helm...
helm repo remove kubeslice-ent
helm repo add kubeslice-ent $HELM_REPO --username $HELM_USER --password $HELM_PASS
helm repo update kubeslice-ent
helm repo list
helm search repo kubeslice-ent

# Controller setup...
echo Switch to controller context and set it up...
kubectx $PREFIX$CONTROLLER
kubectx

helm install cert-manager kubeslice-ent/cert-manager --namespace cert-manager  --create-namespace --set installCRDs=true

echo "Check for cert-manager pods"
kubectl get pods -n cert-manager
echo "Wait for cert-manager to be Running"
namespace=cert-manager
sleep=60
wait_for_pods

kubectl get pods -n cert-manager

# Install kubeslice-controller kubeslice-ent/kubeslice-controller
# First, get the controller's endpoint (sed removes the colors encoded in the cluster-info output)
INTERNALIP=`kubectl get nodes -o wide | grep master | awk '{ print $6 }'`
CONTROLLER_ENDPOINT=$INTERNALIP:6443
echo CONTROLLEREndPoint is: $CONTROLLER_ENDPOINT

DECODE_CONTROLLER_ENDPOINT=`echo -n https://$CONTROLLER_ENDPOINT | base64`
echo Endpoint after base64 is: $DECODE_CONTROLLER_ENDPOINT

# Make a controller values yaml from the controller template yaml
CFILE=$CONTROLLER-config.yaml
cp $CONTROLLER_TEMPLATE $CFILE
sed -i $BSDSED "s/ENDPOINT/$CONTROLLER_ENDPOINT/g" $CFILE

echo "Install the kubeslice-controller"
helm install kubeslice-controller kubeslice-ent/kubeslice-controller -f controller-config.yaml --namespace kubeslice-controller --create-namespace

echo Check for status...
kubectl get pods -n kubeslice-controller
echo "Wait for kubeslice-controller-manager to be Running"
namespace=kubeslice-controller
sleep=180
wait_for_pods

kubectl get pods -n kubeslice-controller

echo kubectl apply -f project.yaml -n kubeslice-controller
kubectl apply -f project.yaml -n kubeslice-controller
sleep 30

echo kubectl get project -n kubeslice-controller
kubectl get project -n kubeslice-controller

echo kubectl get sa -n kubeslice-avesha
kubectl get sa -n kubeslice-avesha

# Clusters registration setup
# Make a clusters-registration.yaml from the clusters-registration.template.yaml
REGFILE=clusters-registration.yaml
echo "Register clusters"
for WORKER in ${WORKERS[@]}; do
    cp $REGISTRATION_TEMPLATE $REGFILE
    sed -i $BSDSED "s/WORKER/$WORKER/g" $REGFILE
    kubectl apply -f clusters-registration.yaml -n kubeslice-avesha
done

echo kubectl get clusters -n kubeslice-avesha
kubectl get clusters -n kubeslice-avesha

# Worker setup
# Get secret info from controller...
for WORKER in ${WORKERS[@]}; do

    kubectx $PREFIX$CONTROLLER

    SECRET=`kubectl get secrets -n kubeslice-avesha| grep $WORKER | awk '{print $1}'`
    echo Secret for worker $WORKER is: $SECRET

    # Don't use endpoint from the secrets file... use the one we created above
    echo "Readable ENDPOINT is: " $DECODE_CONTROLLER_ENDPOINT

    NAMESPACE=`kubectl get secrets $SECRET -o yaml -n kubeslice-avesha | grep -m 1 " namespace" | awk '{print $2}'`
    NAMESPACE=`echo -n $NAMESPACE`
    CACRT=`kubectl get secrets $SECRET -o yaml -n kubeslice-avesha | grep -m 1 " ca.crt" | awk '{print $2}'`
    CACRT=`echo -n $CACRT`
    TOKEN=`kubectl get secrets $SECRET -o yaml -n kubeslice-avesha | grep -m 1 " token" | awk '{print $2}'`
    TOKEN=`echo -n $TOKEN`
    CLUSTERNAME=`echo -n $WORKER`

    if [ "$VERBOSE" == true ]; then
	echo Namespace $NAMESPACE
	echo Endpoint $ENDPOINT
	echo Ca.crt $CACRT
	echo Token $TOKEN
	echo ClusterName $CLUSTERNAME
    fi
    
    # Convert the template info a .yaml for this worker
    WFILE=$WORKER.config.yaml
    cp $WORKER_TEMPLATE $WFILE
    sed -i $BSDSED "s/NAMESPACE/$NAMESPACE/g" $WFILE
    sed -i $BSDSED "s/ENDPOINT/$DECODE_CONTROLLER_ENDPOINT/g" $WFILE
    sed -i $BSDSED "s/CACRT/$CACRT/g" $WFILE
    sed -i $BSDSED "s/TOKEN/$TOKEN/g" $WFILE
    sed -i $BSDSED "s/WORKERNAME/$CLUSTERNAME/g" $WFILE


    # Switch to worker context
    kubectx $PREFIX$WORKER
    WORKERNODEIP=`kubectl get nodes -o wide | grep $WORKER-worker | head -1 | awk '{ print $6 }'`
    sed -i $BSDSED "s/NODEIP/$WORKERNODEIP/g" $WFILE
    helm install kubeslice-worker kubeslice-ent/kubeslice-worker -f $WFILE --namespace kubeslice-system --create-namespace
    sleep 5
    echo Check for status...
    kubectl get pods -n kubeslice-system
    echo "Wait for kubeslice-system to be Running"
    namespace=kubeslice-system
    sleep=300
    wait_for_pods
    kubectl get pods -n kubeslice-system
    # Iperf Namespace
    echo Create Iperf Namespace
    kubectl create ns iperf
done

sleep 120
echo Switch to controller context and configure slices...
kubectx $PREFIX$CONTROLLER
kubectx

# Slice setup
# Make a slice.yaml from the slice.template.yaml
SFILE=slice.yaml
cp $SLICE_TEMPLATE $SFILE

# Check if running in Linux or Mac
if [ "$(uname)" == "Linux" ]; then
    for WORKER in ${WORKERS[@]}; do
        sed -i $BSDSED "s/- WORKER/- $WORKER/g" $SFILE
        sed -i $BSDSED "/- $WORKER/ a \ \ \ \ - WORKER" $SFILE
    done
elif [ "$(uname)" == "Darwin" ]; then
    for WORKER in ${WORKERS[@]}; do
        sed -i $BSDSED "s/- WORKER/- $WORKER/g" $SFILE
        sed -i $BSDSED '14i\
\
' $SFILE
      sed -i $BSDSED '14i\             
    - WORKER' $SFILE
    done
fi
sed -i $BSDSED '/- WORKER/d' $SFILE

echo kubectl apply -f $SFILE -n kubeslice-avesha
kubectl apply -f $SFILE -n kubeslice-avesha

echo "Wait for vl3(slice) and gateway pod to be Running in worker clusters"

echo "Final status check..."
for WORKER in ${WORKERS[@]}; do
    echo $PREFIX$WORKER
    kubectx $PREFIX$WORKER
    namespace=kubeslice-system
    sleep=240
    wait_for_pods
    kubectx
    kubectl get pods -n kubeslice-system
done


# Iperf setup
echo Setup Iperf
# Switch to kind-worker-1 context
kubectx $PREFIX${WORKERS[0]}
kubectx

kubectl apply -f iperf-sleep.yaml -n iperf
echo "Wait for iperf to be Running"
namespace=iperf
sleep=180
wait_for_pods
kubectl get pods -n iperf

# Switch to kind-worker-2 context
for WORKER in ${WORKERS[@]}; do
    if [[ $WORKER -ne ${WORKERS[0]} ]]; then 
        kubectx $PREFIX$WORKER
        kubectx
        kubectl apply -f iperf-server.yaml -n iperf
        echo "Wait for iperf to be Running"
        namespace=iperf
        sleep=180
        wait_for_pods
        kubectl get pods -n iperf
    fi
done

# Switch to worker context
kubectx $PREFIX${WORKERS[0]}
kubectx

sleep 90
# Check Iperf connectity from iperf sleep to iperf server
IPERF_CLIENT_POD=`kubectl get pods -n iperf | grep iperf-sleep | awk '{ print$1 }'`

kubectl exec -it $IPERF_CLIENT_POD -c iperf -n iperf -- iperf -c iperf-server.iperf.svc.slice.local -p 5201 -i 1 -b 10Mb;
if [ $? -ne 0 ]; then
    echo '***Error: Connectivity between clusters not succesful!'
    ERR=$((ERR+1))
fi

# Kubeslice Enterprise setup...
echo Initializing Kubeslice Enterprise Setup...
kubectx $PREFIX$CONTROLLER
kubectx

echo Deploying Kubeslice Enterprise Helm Charts...
helm install kubeslice-ent kubeslice-ent/kubeslice-ui --set imagePullSecrets.repository=$DOCKER_REPO --set imagePullSecrets.username=$DOCKER_USER --set imagePullSecrets.password=$DOCKER_PASS --set imagePullSecrets.email=$DOCKER_EMAIL -n kubeslice-controller

echo "Check for Kubeslice Enterprise pod"
kubectl get pods -n kubeslice-controller
kubectl get pods -n kubernetes-dashboard

namespace=kubeslice-controller
sleep=120
wait_for_pods

namespace=kubeslice-controller
sleep=60
wait_for_pods

kubectl get pods -n kubeslice-controller

namespace=kubernetes-dashboard
sleep=60
wait_for_pods

kubectl get pods -n kubernetes-dashboard

echo Creating the Kubeconfig file used to access the KubeSlice UI. 

# Getting the Secrets for the Service Account
# Cosmetics for the created config
clusterName=$PREFIX$CONTROLLER
# your server address goes here get it via `kubectl cluster-info`
server=$controllerendpoint
# the Namespace and ServiceAccount name that is used for the config
namespace=$PJTNAMESPACE
serviceAccount=$SERVICEACCOUNT

secretName=$(kubectl --namespace $namespace get serviceAccount $serviceAccount -o jsonpath='{.secrets[0].name}')
ca=$(kubectl --namespace $namespace get secret/$secretName -o jsonpath='{.data.ca\.crt}')
token=$(kubectl --namespace $namespace get secret/$secretName -o jsonpath='{.data.token}' | base64 --decode)

cat << EOF > kubeconfig.yaml
---
apiVersion: v1
kind: Config
clusters:
  - name: ${clusterName}
    cluster:
      certificate-authority-data: ${ca}
      server: ${server}
contexts:
  - name: ${serviceAccount}@${clusterName}
    context:
      cluster: ${clusterName}
      namespace: ${namespace}
      user: ${serviceAccount}
users:
  - name: ${serviceAccount}
    user:
      token: ${token}
current-context: ${serviceAccount}@${clusterName}
EOF

echo Please use the Kubeconfig file in the loation $(pwd) to login into Avesha KubeSlice UI

echo "Fetch the URL to access the Kubeslice Enterprise UI"
TARGETPORT=`kubectl get services -n kubeslice-controller | egrep 'kubeslice-ui-proxy' | awk '{ print $5 }' | cut -c 5-9`

echo Script run time is $(expr `date +%M` - $start_time) m
start_time=0

echo -e "\n Started forwarding the port to access the Kubeslice UI"
echo -e "\n Please use the CTRL-C command to exit & stop the port forwarding to the Kubeslice UI &"
echo -e "\n Please use the below command to access the UI manually"
echo -e "\n kubectl port-forward svc/kubeslice-ui-proxy -n kubeslice-controller $TARGETPORT:443"
echo -e "\n Please use the URL to login into 'Avesha KubeSlice' is: https://localhost:$TARGETPORT"

kubectl port-forward svc/kubeslice-ui-proxy -n kubeslice-controller $TARGETPORT:443

# Return status
exit $ERR
