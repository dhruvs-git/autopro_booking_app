# COGNITO USER POOL
# The database of all users. Handles sign-up, login, password reset.

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}-user-pool"

  # --- Login method ---
  username_attributes      = ["email"] # users log in with email
  auto_verified_attributes = ["email"] # auto send verification code

  # --- Password policy ---
  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # --- Email verification message ---
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Autoserve-Pro Verify your email"
    email_message        = "Your verification code is {####}"
  }

  # --- Account recovery ---
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  # --- MFA off for now, enable in production
  mfa_configuration = "OFF" # "ON", "OFF", or "OPTIONAL"

  tags = {
    Name = "${var.name_prefix}-user-pool"
  }
}




# USER POOL CLIENT
# How your frontend app talks to Cognito.
# This is the "app registration" — Cognito needs to know which app
# is allowed to authenticate users.

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # --- Token expiry ---
  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 30 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # --- Auth flows ---
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH", # email + password login
    "ALLOW_REFRESH_TOKEN_AUTH", # allow token refresh
    "ALLOW_USER_SRP_AUTH"       # secure remote password (recommended)
  ]

  # --- Security ---
  prevent_user_existence_errors = "ENABLED" # hides if user exists or not

  generate_secret = false # true if server-side app, false for frontend/mobile
}


# USER GROUPS
# Groups determine what a user can do inside Flask.
# Flask reads the group from the JWT token on every request.

resource "aws_cognito_user_group" "customers" {
  name         = "customers"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Regular customers — can create and view their own bookings"
  precedence   = 2
}

resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Admins — can view all bookings and update status"
  precedence   = 1
}




# CREATING ADMIN USER

resource "aws_cognito_user" "admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.admin_email

  # --- User attributes ---
  attributes = {
    email          = var.admin_email
    email_verified = true
  }

  # --- Temporary password ---
  temporary_password = "Autopro@2025!"

  # --- Force user to change password on first login ---
  message_action = "SUPPRESS" # "SUPPRESS" = don't send welcome email
  # "RESEND"   = resend welcome email

}


# ADDING ADMIN IN THE USER GROUP ADMIN

resource "aws_cognito_user_in_group" "my_user_in_group" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.admins.name
  username     = aws_cognito_user.admin.username
}

