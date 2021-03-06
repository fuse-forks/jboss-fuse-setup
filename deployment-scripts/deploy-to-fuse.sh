#!/bin/sh
###
# Script to create the Fabric and containers
###

FUSE_PATH=$1

# Full path of your ssh, used by the aliases
SSH_PATH=$(which ssh)

# Configure logging to print line numbers
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# ulimits values needed by the processes inside the container
ulimit -u 4096
ulimit -n 4096

# Set debug mode
set -x

# Halt on errors
set -e

# Alias to connect to the ssh server exposed by JBoss Fuse. Uses sshpass to script the password authentication
alias ssh2fabric="sshpass -p admin $SSH_PATH -p 8101 -o ServerAliveCountMax=100 -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR admin@localhost"

# Start fuse on root node (yes, that initial backslash is required to not use the declared alias)
"$FUSE_PATH/bin/start"

# Wait for ssh server to be up, avoids "Connection reset by peer" errors
while ! ssh2fabric "echo up" ; do sleep 1s; done;

# Wait for critical components to be available before progressing with other steps
ssh2fabric "wait-for-service -t 300000 io.fabric8.api.BootstrapComplete"

# Create a new fabric AND wait for the Fabric to be up and ready to accept the following commands
ssh2fabric "fabric:create --clean --resolver localip --global-resolver localip --wait-for-provisioning --profile fabric" 

# Configure local maven/nexus
ssh2fabric "fabric:profile-edit --append --pid io.fabric8.agent/org.ops4j.pax.url.mvn.repositories=\"file:/Users/garethah/.m2/repository@snapshots@id=maven-snapshots\" default"
ssh2fabric "fabric:profile-edit --append --pid io.fabric8.agent/org.ops4j.pax.url.mvn.repositories=\"http://localhost:8081/nexus/content/repositories/releases/@releases@id=local-releases\" default"
ssh2fabric "fabric:profile-edit --append --pid io.fabric8.agent/org.ops4j.pax.url.mvn.repositories=\"http://localhost:8081/nexus/content/repositories/snapshots/@snapshots@id=local-snapshots\" default"

# Important! to disable maven snapshot checksum that otherwise will block the functionality
ssh2fabric "fabric:profile-edit --pid org.fusesource.fabric.maven/checksumPolicy=warn  default "
ssh2fabric "fabric:profile-edit --pid org.ops4j.pax.url.mvn/checksumPolicy=warn  default "

# Add in the zookeeper commands to fabric, helps if we have issues in the future
ssh2fabric "fabric:profile-edit --features fabric-zookeeper-commands fabric"

# Install scripts which will create the containers and profiles
ssh2fabric "shell:source mvn:com.garethahealy/karaf-scripts/1.0.0-SNAPSHOT/karaf/create-containers"
ssh2fabric "shell:source mvn:com.garethahealy/karaf-scripts/1.0.0-SNAPSHOT/karaf/create-profiles"
ssh2fabric "shell:source mvn:com.garethahealy/karaf-scripts/1.0.0-SNAPSHOT/karaf/upgrade-containers"
ssh2fabric "shell:source mvn:com.garethahealy/karaf-scripts/1.0.0-SNAPSHOT/karaf/assign-profiles"

# Set debug mode off
set +x

echo "
----------------------------------------------------
CI Quickstart
----------------------------------------------------
FABRIC ROOT: 
- karaf:       $FUSE_PATH/bin/client -u admin -p admin
- tail logs:   tail -F $FUSE_PATH/data/log/fuse.log
----------------------------------------------------
"

