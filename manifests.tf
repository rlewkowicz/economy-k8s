resource "null_resource" "manifests" {
  depends_on = [
    module.efs,
    module.eks_cluster.kubernetes_config_map_id,
    helm_release.aws_efs
  ]
  provisioner "local-exec" {
    command = <<-EOF
    aws eks update-kubeconfig --name ${module.eks_cluster.eks_cluster_id}
    cat <<EOD | sed 's/##FS_ID##/${module.efs.id}/g' | kubectl apply -f -
    ${file("${path.module}/files/storageclass.yaml")}
    EOD
    EOF
  }
}

resource "helm_release" "aws_efs" {
  depends_on = [
    module.efs,
    module.eks_cluster.kubernetes_config_map_id,
    kubernetes_service_account.efs-csi-controller-sa
  ]

  name         = "aws-efs-csi-driver"
  repository   = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart        = "aws-efs-csi-driver"
  namespace    = "kube-system"
  force_update = true

  set {
    name  = "controller.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

}
