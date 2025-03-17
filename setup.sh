#!/bin/bash

set -e

log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "Error: $1 command not found."; exit 1; }
}

create_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log "Creating namespace $namespace"
        kubectl create namespace "$namespace"
    else
        log "Namespace $namespace already exists"
    fi
}


install_vpa() {
    log "Installing Vertical Pod Autoscaler (VPA)"
    git clone https://github.com/kubernetes/autoscaler.git
    cd ./autoscaler/vertical-pod-autoscaler || exit
    ./hack/vpa-up.sh
    cd ../..
    rm -rf ./autoscaler
    log "VPA installation complete"
}


install_goldilocks() {
    log "Installing Fairwinds Goldilocks"
    git clone https://github.com/FairwindsOps/goldilocks.git
    cd ./goldilocks || exit
    create_namespace goldilocks
    kubectl -n goldilocks apply -f hack/manifests/controller
    kubectl -n goldilocks apply -f hack/manifests/dashboard
    cd ..
    rm -rf ./goldilocks
    log "Fairwinds Goldilocks installation complete"
}



port_forward_goldilocks() {
    log "Checking for Goldilocks dashboard pod with labels app.kubernetes.io/component=dashboard and app.kubernetes.io/name=goldilocks"


    pod_name=$(kubectl get pods -n goldilocks -l app.kubernetes.io/component=dashboard,app.kubernetes.io/name=goldilocks -o jsonpath='{.items[0].metadata.name}')


    if [[ -z "$pod_name" ]]; then
        log "Error: Goldilocks dashboard pod not found with the specified labels."
        exit 1
    fi

    log "Found Goldilocks dashboard pod: $pod_name. Waiting for it to be ready..."


    kubectl wait --for=condition=ready pod/"$pod_name" -n goldilocks --timeout=300s


    log "Goldilocks dashboard pod is ready. Starting port-forwarding..."
    kubectl -n goldilocks port-forward svc/goldilocks-dashboard 8080:80 &
    
    log "Goldilocks dashboard is now accessible at http://localhost:8080"
}


label_namespace_qos() {
    log "Labeling qos namespace for Goldilocks"
    kubectl label ns qos goldilocks.fairwinds.com/enabled=true --overwrite
    log "Namespace 'qos' labeled successfully"
}


deploy_applications() {
    log "Deploying applications"


    kubectl apply -f ./kubernetes-deployments/guaranteed.yaml
    kubectl apply -f ./kubernetes-vertical-pod-autoscalers/guaranteed.yaml


    kubectl apply -f ./kubernetes-deployments/burstable.yaml
    kubectl apply -f ./kubernetes-vertical-pod-autoscalers/burstable.yaml


    kubectl apply -f ./kubernetes-deployments/besteffort.yaml
    kubectl apply -f ./kubernetes-vertical-pod-autoscalers/besteffort.yaml


    kubectl apply -f ./kubernetes-deployments/traffic-generator.yaml
    kubectl apply -f ./kubernetes-vertical-pod-autoscalers/traffic-generator.yaml

    log "Applications deployed successfully"
}

open_traffic_generator_terminal() {
    log "Searching for traffic-generator pod"

    pod_name=$(kubectl get pods -l app=traffic-generator -n qos -o jsonpath='{.items[0].metadata.name}')

    if [[ -z "$pod_name" ]]; then
        log "Error: Traffic Generator pod not found."
        exit 1
    fi

    log "Found Traffic Generator pod: $pod_name. Opening terminal to SSH into it."

    if command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash -c "kubectl exec -n qos -it $pod_name -- bash; exec bash"
        else
            log "Open a new terminal and run 'kubectl exec -n qos -it $pod_name -- bash'"
    fi

    log "In the terminal, you can now run the following command to start the stress test: stress --cpu 1 --vm 1 --vm-bytes 500M --timeout 1200s"
}

open_goldilocks_dashboard() {
    if command -v xdg-open &> /dev/null; then
        log "Opening Goldilocks dashboard in the browser at http://localhost:8080"
        xdg-open http://localhost:8080
    else
        log "Open Goldilocks dashbord in your browser at http://localhost:8080"
    fi
}

main() {
    log "Starting script execution"

    check_command kubectl
    
    check_command git

    create_namespace qos

    install_vpa

    install_goldilocks

    port_forward_goldilocks

    label_namespace_qos

    deploy_applications

    open_traffic_generator_terminal

    open_goldilocks_dashboard

    log "Script execution complete"
}

main
