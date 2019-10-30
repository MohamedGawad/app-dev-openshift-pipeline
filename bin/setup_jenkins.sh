#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git shared.na.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

oc version

# Set up Jenkins with sufficient resources
# DO NOT FORGET TO PASS '-n ${GUID}-jenkins to ALL commands!!'
# You do not want to set up things in the wrong project.
oc new-app jenkins-persistent -n ${GUID}-jenkins --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi \
--param DISABLE_ADMINISTRATIVE_MONITORS=true

oc set resources dc jenkins -n ${GUID}-jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m


# Create custom agent container image with skopeo.
# Build config must be called 'jenkins-agent-appdev' for the test below to succeed
oc new-build --strategy=docker -D $'FROM quay.io/openshift/origin-jenkins-agent-maven:4.1.0\n
   USER root\n
   RUN curl https://copr.fedorainfracloud.org/coprs/alsadi/dumb-init/repo/epel-7/alsadi-dumb-init-epel-7.repo -o /etc/yum.repos.d/alsadi-dumb-init-epel-7.repo && \ \n
   curl https://raw.githubusercontent.com/cloudrouter/centos-repo/master/CentOS-Base.repo -o /etc/yum.repos.d/CentOS-Base.repo && \ \n
   curl http://mirror.centos.org/centos-7/7/os/x86_64/RPM-GPG-KEY-CentOS-7 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 && \ \n
   DISABLES="--disablerepo=rhel-server-extras --disablerepo=rhel-server --disablerepo=rhel-fast-datapath --disablerepo=rhel-server-optional --disablerepo=rhel-server-ose --disablerepo=rhel-server-rhscl" && \ \n
   yum $DISABLES -y --setopt=tsflags=nodocs install skopeo && yum clean all\n
   USER 1001' --name=jenkins-agent-appdev -n ${GUID}-jenkins


# Create Secret with credentials to access the private repository
# You may hardcode your user id and password here because
# this shell scripts lives in a private repository
# Passing it from Jenkins would show it in the Jenkins Log
oc create secret generic gitea-creds --from-literal=user=bgottfri-redhat.com --from-literal=password=r3dh4t1! -n ${GUID}-jenkins



# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
# Build config has to be called 'tasks-pipeline'.
# Make sure you use your secret to access the repository
NEWBUILDCOMMAND="oc new-build http://homework-gitea.apps.shared.na.openshift.opentlc.com/bgottfri-redhat.com/ocp4_app_deploy_homework.git --name=tasks-pipeline --strategy=pipeline --context-dir=openshift-tasks --source-secret=gitea-creds -n ${GUID}-jenkins"
echo $NEWBUILDCOMMAND
$NEWBUILDCOMMAND
#oc new-build http://homework-gitea.apps.shared.na.openshift.opentlc.com/bgottfri-redhat.com/ocp4_app_deploy_homework.git --name=tasks-pipeline --strategy=pipeline --context-dir=openshift-tasks --source-secret=gitea-creds -n ${GUID}-jenkins



# ========================================
# No changes are necessary below this line
# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

# Make sure that Jenkins Agent Build Pod has finished building
while : ; do
  echo "Checking if Jenkins Agent Build Pod has finished building..."
  AVAILABLE_REPLICAS=$(oc get pod jenkins-agent-appdev-1-build -n ${GUID}-jenkins -o=jsonpath='{.status.phase}')
  if [[ "$AVAILABLE_REPLICAS" == "Succeeded" ]]; then
    echo "...Yes. Jenkins Agent Build Pod has finished."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done