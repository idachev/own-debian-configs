#!/bin/bash

date
echo Y | /usr/bin/ssh idachev@nimbus-gateway.eng.vmware.com "NIMBUS=sc-prd-vc015 /mts/git/bin/nimbus-ctl --lease 7 extend_lease idachev-test-nfs-10"

