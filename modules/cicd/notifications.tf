resource "aws_sns_topic" "pipeline" {
  name              = "${var.name}-pipeline-notificacoes"
  kms_master_key_id = aws_kms_key.this.arn
}

data "aws_iam_policy_document" "sns" {
  statement {
    sid = "DonoDaConta"
    actions = [
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:AddPermission",
      "sns:RemovePermission",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:Publish",
    ]
    resources = [aws_sns_topic.pipeline.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account}:root"]
    }
  }

  statement {
    sid       = "NotificacoesDoPipeline"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline.arn]
    principals {
      type        = "Service"
      identifiers = ["codestar-notifications.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }

  statement {
    sid       = "SomenteTLS"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "pipeline" {
  arn    = aws_sns_topic.pipeline.arn
  policy = data.aws_iam_policy_document.sns.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = each.value
}

# O pedido de aprovação sai pela própria ação (NotificationArn); aqui só o desfecho.
resource "aws_codestarnotifications_notification_rule" "pipeline" {
  name        = "${var.name}-pipeline-desfecho"
  resource    = aws_codepipeline.this.arn
  detail_type = "BASIC"
  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-succeeded",
  ]

  target {
    address = aws_sns_topic.pipeline.arn
  }

  depends_on = [aws_sns_topic_policy.pipeline]
}
