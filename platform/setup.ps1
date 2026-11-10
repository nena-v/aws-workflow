# platform/setup.ps1
$ErrorActionPreference = "Stop"

# --- à adapter ---
$AwsRegion   = "us-west-2"
$Name        = "checkout-demo"
$GitHubOwner = "nena-v"
$GitHubRepo  = "aws-workflow"

# 1. identifiants immuables du propriétaire et du dépôt, pour la trust policy
$OwnerId = (Invoke-RestMethod "https://api.github.com/users/$GitHubOwner").id
$RepoId  = (Invoke-RestMethod "https://api.github.com/repos/$GitHubOwner/$GitHubRepo").id
$Account = aws sts get-caller-identity --query Account --output text
$Uri     = "$Account.dkr.ecr.$AwsRegion.amazonaws.com/$Name"

# 2. dépôt ECR : tags immuables, scan au push
aws ecr create-repository --repository-name $Name `
  --image-tag-mutability IMMUTABLE --image-scanning-config scanOnPush=true

# 3. rôle d'exécution de la fonction (écrire les logs)
aws iam create-role --role-name "$Name-execution" --assume-role-policy-document `
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name "$Name-execution" `
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 4. image initiale, pour que le site tourne avant la démo
# le push passe par amazon-ecr-credential-helper : pas de docker login
$PreviousProfile = $env:AWS_PROFILE
$env:AWS_PROFILE = "ecr-helper"
docker build --build-arg APP_VERSION=init -t "$($Uri):init" app
docker push "$($Uri):init"
$env:AWS_PROFILE = $PreviousProfile

# 5. fonction Lambda, version 1 (immuable), alias prod, URL publique
aws lambda create-function --function-name $Name --package-type Image `
  --code "ImageUri=$($Uri):init" `
  --role "arn:aws:iam::$($Account):role/$Name-execution"
aws lambda wait function-active --function-name $Name
aws lambda publish-version --function-name $Name
aws lambda create-alias --function-name $Name --name prod --function-version 1
aws lambda create-function-url-config --function-name $Name --qualifier prod --auth-type NONE

# 6. fédération OIDC : fournisseur d'identité, puis rôle du pipeline
# (empreinte ignorée par AWS pour GitHub : AWS valide ses propres AC racines)
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com `
  --client-id-list sts.amazonaws.com `
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

$Sub = "repo:$GitHubOwner@$OwnerId/$GitHubRepo@$($RepoId):ref:refs/heads/main"
$Trust = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$($Account):oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": { "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "$Sub"
    } }
  }]
}
"@
$Perms = @"
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["ecr:PutImage","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:BatchCheckLayerAvailability","ecr:BatchGetImage"],
      "Resource": "arn:aws:ecr:$($AwsRegion):$($Account):repository/$Name" },
    { "Effect": "Allow",
      "Action": ["lambda:UpdateFunctionCode","lambda:GetFunction"],
      "Resource": "arn:aws:lambda:$($AwsRegion):$($Account):function:$Name" },
    { "Effect": "Allow",
      "Action": "lambda:UpdateAlias",
      "Resource": "arn:aws:lambda:$($AwsRegion):$($Account):function:$Name:prod" }
  ]
}
"@
aws iam create-role --role-name github-demo-deployer --assume-role-policy-document "$Trust"
aws iam put-role-policy --role-name github-demo-deployer --policy-name deploy --policy-document "$Perms"

# 7. variables GitHub
gh variable set AWS_ROLE_ARN --body "arn:aws:iam::$($Account):role/github-demo-deployer"
$AppUrl = aws lambda get-function-url-config --function-name $Name --query FunctionUrl --output text
gh variable set APP_URL --body $AppUrl

Write-Host "Prêt : $AppUrl"