# ---------------------------------------------------------------------------
# Subscription budget with alerts at 50%, 80% and 100% of actual cost.
# A budget only alerts. It never stops spending. The Azure for Students credit
# spending limit is what stops resources when the credit runs out.
# ---------------------------------------------------------------------------
resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "bastion-monthly"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      threshold_type = "Actual"
      operator       = "GreaterThanOrEqualTo"
      contact_emails = var.budget_alert_emails
    }
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_alert_emails
  }

  lifecycle {
    # Azure moves the start date forward on its own; do not report that as drift.
    ignore_changes = [time_period]
  }
}

# ---------------------------------------------------------------------------
# Defender for Cloud: foundational CSPM only (the free tier). No paid plan is
# ever enabled by Bastion; opa/ rejects any plan with tier "Standard".
# ---------------------------------------------------------------------------
resource "azurerm_security_center_subscription_pricing" "cspm_free" {
  #checkov:skip=CKV_AZURE_19:Paid Defender plans are out of budget on Azure for Students. Foundational CSPM (Free) is the deliberate choice; see docs/COST.md.
  tier          = "Free"
  resource_type = "CloudPosture"
}

# Security contact: Defender for Cloud sends its (free tier) security alerts and
# attack-path notifications here, and to subscription owners. Free.
resource "azurerm_security_center_contact" "default" {
  #checkov:skip=CKV_AZURE_20:A phone number would be personal data in a public repository; email alerts are enough for a lab.
  name                = "default"
  email               = var.budget_alert_emails[0]
  alert_notifications = true
  alerts_to_admins    = true
}
