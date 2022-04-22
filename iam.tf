resource "aws_iam_policy" "external_dns_policy" {
  name        = "${module.eks_cluster.eks_cluster_id}-external-dns"
  description = "policy to allow k8s external dns for ${module.eks_cluster.eks_cluster_id}"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ChangeResourceRecordSets"
        ],
        "Resource" : [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "efs_csi_policy" {
  name        = "${module.eks_cluster.eks_cluster_id}-efs_csi_policy"
  description = "${module.eks_cluster.eks_cluster_id} efs csi policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:CreateAccessPoint"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringLike" : {
            "aws:RequestTag/efs.csi.aws.com/cluster" : "true"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : "elasticfilesystem:DeleteAccessPoint",
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/efs.csi.aws.com/cluster" : "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "efs_csi_role" {
  depends_on = [module.eks_cluster.eks_cluster_identity_oidc_issuer_arn]
  name       = "${module.eks_cluster.eks_cluster_id}-efs-csi-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Federated" : "${module.eks_cluster.eks_cluster_identity_oidc_issuer_arn}"
          },
          "Action" : "sts:AssumeRoleWithWebIdentity",
          "Condition" : {
            "StringEquals" : {
              "${replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "")}:sub" : "system:serviceaccount:kube-system:efs-csi-controller-sa",
              "${replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "")}:aud" : "sts.amazonaws.com"
            }
          }
        }
      ]
    }
  )
}

resource "kubernetes_service_account" "efs-csi-controller-sa" {
  metadata {
    name        = "efs-csi-controller-sa"
    namespace   = "kube-system"
    annotations = { "eks.amazonaws.com/role-arn" : "${aws_iam_role.efs_csi_role.arn}" }
  }
}

resource "aws_iam_role" "external_dns_controller_role" {
  depends_on = [module.eks_cluster.eks_cluster_identity_oidc_issuer_arn]
  name       = "${module.eks_cluster.eks_cluster_id}-external-dns"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Federated" : "${module.eks_cluster.eks_cluster_identity_oidc_issuer_arn}"
          },
          "Action" : "sts:AssumeRoleWithWebIdentity",
          "Condition" : {
            "StringEquals" : {
              "${replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "")}:sub" : "system:serviceaccount:external-dns:external-dns-controller",
              "${replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "")}:aud" : "sts.amazonaws.com"
            }
          }
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "external_dns_policy_external_dns_controller_role" {
  policy_arn = aws_iam_policy.external_dns_policy.arn
  role       = aws_iam_role.external_dns_controller_role.name
  depends_on = [aws_iam_role.external_dns_controller_role]
}

resource "aws_iam_role_policy_attachment" "efs_controller" {
  policy_arn = aws_iam_policy.efs_csi_policy.arn
  role       = aws_iam_role.efs_csi_role.name
  depends_on = [aws_iam_role.efs_csi_role]
}