output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "pod_identity_agent_ready" {
  description = "Reference this in depends_on / implicit ordering for modules whose controllers need Pod Identity (Karpenter, LB Controller, external-dns, ...)."
  value       = aws_eks_addon.pod_identity_agent.id
}
