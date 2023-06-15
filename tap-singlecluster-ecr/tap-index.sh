
source var.conf

chmod +x tap-aws-preq.sh
chmod +x tap-full-profile-install.sh
chmod +x tanzu-java-web-app-workload.sh

echo "Step 1 => installing tap aws prreq (eks , ecr ) !!!"
./tap-aws-preq.sh
echo "Step 2 => Setup TAP full profile Cluster"
./tap-full-profile-install.sh
echo "Step 3 => deploy sample app"
./ tanzu-java-web-app-workload.sh
