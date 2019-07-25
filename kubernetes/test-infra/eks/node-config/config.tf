provider "kubernetes" {
  config_path      = local_file.kubeconfig.filename
  load_config_file = true
}

resource "local_file" "kubeconfig" {
  content  = var.kubeconfig
  filename = "${path.module}/kubeconfig"
}

locals {
  mapped_role_format = <<MAPPEDROLE
- rolearn: %s
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
MAPPEDROLE

}

resource "local_file" "cluster_ca" {
  content = base64decode(var.cluster_ca)
  filename = "${path.root}/cluster_ca"
}

resource "null_resource" "wait_for_api" {
  depends_on = [local_file.cluster_ca]

  provisioner "local-exec" {
    working_dir = path.root
    environment = {
      K8S_CA_FILE = abspath(local_file.cluster_ca.filename)
      K8S_ENDPOINT = var.cluster_endpoint
    }
    command = <<CMDEOF
while ! curl -s --cacert $K8S_CA_FILE $K8S_ENDPOINT/version; do 
  echo "Waiting for the cluster API to come online..."
  sleep 3
done
CMDEOF

  }
}

resource "kubernetes_config_map" "name" {
  depends_on = [null_resource.wait_for_api]

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = join(
      "\n",
      formatlist(local.mapped_role_format, var.k8s_node_role_arn),
    )
  }
}
