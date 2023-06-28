
source var.conf

chmod +x tap-eks.sh
chmod +x tanzu-essential-setup.sh
chmod +x tap-dev-namespace.sh
chmod +x tap-gitops-sops.sh
chmod +x tanzu-java-web-app.sh
chmod +x dns_update_route53.sh


chmod +x tanzu-java-web-app-workload.sh

echo "Step 1 => installing tap aws prreq (eks , vpc ) !!!"
./tap-eks.sh
echo "Step 2 => Install tanzu essential"
./tanzu-essential-setup.sh

echo "Step 3 => tap git ops operation"
./tap-gitops-sops.sh

echo "Step 4  => installing TAP developer namespace in tap cluster !!! "
./tap-dev-namespace.sh

echo "Step 4  => update envoy lb into route53 dns record !!! "
./dns_update_route53.sh

echo "Step 6  => deploy sample app"
./tanzu-java-web-app.sh
