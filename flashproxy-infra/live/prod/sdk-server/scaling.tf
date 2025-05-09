#########################################
# scaling.tf – autoscale sdk-server ASG
# • Same thresholds & warm-up logic as sdk-gateway
#########################################

locals {
  lb_id  = aws_lb.sdk_srv_nlb.arn_suffix           # net/sdk-server-nlb/…
  tg_id  = aws_lb_target_group.sdk_srv_tg.arn_suffix
  asg_id = aws_autoscaling_group.sdk_srv_asg.name
}

############################
# 1. Flows-per-instance math
############################
resource "aws_cloudwatch_metric_alarm" "flows_per_instance_math" {
  alarm_name          = "sdk-srv-math-FlowsPerInstance"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id = "raw_flows"
    metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "ActiveFlowCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = local.lb_id }
    }
  }

  metric_query { id = "flows"  expression = "FILL(raw_flows, 0)" }

  metric_query {
    id = "raw_hosts"
    metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "HealthyHostCount"
      period      = 60
      stat        = "Average"
      dimensions  = {
        LoadBalancer = local.lb_id
        TargetGroup  = local.tg_id
      }
    }
  }

  metric_query { id = "hosts" expression = "FILL(raw_hosts, 1)" }

  metric_query {
    id          = "fpi"
    expression  = "flows / hosts"
    label       = "FlowsPerInstance"
    return_data = true
  }
}

############################
# 2. Step-scaling policies
############################
resource "aws_autoscaling_policy" "scale_out" {
  name                    = "sdk-srv-scale-out"
  autoscaling_group_name  = local.asg_id
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"

  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment          = 1
  }
}

resource "aws_autoscaling_policy" "scale_in" {
  name                    = "sdk-srv-scale-in"
  autoscaling_group_name  = local.asg_id
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
}

############################
# 3a. High-flow alarm
############################
resource "aws_cloudwatch_metric_alarm" "high_flows" {
  alarm_name          = "sdk-srv-HighFlows"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 200
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  metric_query { id = "raw_flows" metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "ActiveFlowCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = local.lb_id } } }

  metric_query { id = "flows"  expression = "FILL(raw_flows, 0)" }

  metric_query { id = "raw_hosts" metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "HealthyHostCount"
      period      = 60
      stat        = "Average"
      dimensions  = {
        LoadBalancer = local.lb_id
        TargetGroup  = local.tg_id } } }

  metric_query { id = "hosts" expression = "FILL(raw_hosts, 1)" }

  metric_query {
    id          = "fpi"
    expression  = "flows / hosts"
    label       = "FlowsPerInstance"
    return_data = true
  }
}

############################
# 3b. Low-flow alarm (12 min)
############################
resource "aws_cloudwatch_metric_alarm" "low_flows" {
  alarm_name          = "sdk-srv-LowFlows"
  evaluation_periods  = 12
  datapoints_to_alarm = 12
  threshold           = 50
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  metric_query { id = "raw_flows" metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "ActiveFlowCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = local.lb_id } } }

  metric_query { id = "flows"  expression = "FILL(raw_flows, 0)" }

  metric_query { id = "raw_hosts" metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "HealthyHostCount"
      period      = 60
      stat        = "Average"
      dimensions  = {
        LoadBalancer = local.lb_id
        TargetGroup  = local.tg_id } } }

  metric_query { id = "hosts" expression = "FILL(raw_hosts, 1)" }

  metric_query {
    id          = "fpi"
    expression  = "flows / hosts"
    label       = "FlowsPerInstance"
    return_data = true
  }
}

############################
# 4. Low CPU-credit alarm
############################
resource "aws_cloudwatch_metric_alarm" "low_cpu_credit" {
  alarm_name          = "sdk-srv-LowCPUCredits"
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 20
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = local.asg_id }
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
}
