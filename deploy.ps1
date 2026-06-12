# OWASP Juice Shop on AWS ECS - Automated Deployment Script
# Windows PowerShell
# Run as Administrator for best results

# Color output functions
function Write-Header {
    param([string]$Message)
    Write-Host "`n" -ForegroundColor White
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

# Main script starts here
Clear-Host
Write-Header "OWASP Juice Shop on AWS ECS - Automated Deployment"

# ====== STEP 1: CHECK PREREQUISITES ======
Write-Header "Step 1: Checking Prerequisites"

# Check AWS CLI
Write-Info "Checking AWS CLI installation..."
try {
    aws --version | Out-Null
    Write-Success "AWS CLI is installed"
} catch {
    Write-Error-Custom "AWS CLI not found. Please install it from: https://aws.amazon.com/cli/"
    Write-Info "After installation, restart PowerShell and run this script again."
    exit 1
}

# Check Terraform or OpenTofu
Write-Info "Checking Terraform/OpenTofu installation..."
$terraformExists = $false
$tofu = $false

try {
    terraform --version | Out-Null
    Write-Success "Terraform is installed"
    $terraformExists = $true
} catch {
    Write-Info "Terraform not found, checking for OpenTofu..."
}

if (-not $terraformExists) {
    try {
        tofu --version | Out-Null
        Write-Success "OpenTofu is installed"
        $tofu = $true
    } catch {
        Write-Error-Custom "Neither Terraform nor OpenTofu found."
        Write-Info "Please install one from:"
        Write-Info "  - Terraform: https://www.terraform.io/downloads"
        Write-Info "  - OpenTofu: https://opentofu.org/docs/intro/install/"
        exit 1
    }
}

$tfCommand = if ($tofu) { "tofu" } else { "terraform" }
Write-Success "Using: $tfCommand"

# ====== STEP 2: AWS PROFILE SETUP ======
Write-Header "Step 2: AWS Profile Configuration"

Write-Info "Enter your AWS Profile name (default: 'juice-shop'):"
$profileName = Read-Host "Profile Name"
if ([string]::IsNullOrWhiteSpace($profileName)) {
    $profileName = "juice-shop"
}

# Check if profile exists
Write-Info "Checking if AWS profile '$profileName' exists..."
try {
    aws sts get-caller-identity --profile $profileName | Out-Null
    Write-Success "AWS profile '$profileName' is configured and working!"
} catch {
    Write-Error-Custom "Profile '$profileName' not found or invalid."
    Write-Info "Creating new AWS profile: $profileName"
    Write-Info "You'll need your AWS Access Key ID and Secret Access Key"
    
    Read-Host "Press Enter to continue with 'aws configure'"
    aws configure --profile $profileName
    
    # Verify it worked
    try {
        aws sts get-caller-identity --profile $profileName | Out-Null
        Write-Success "AWS profile '$profileName' created successfully!"
    } catch {
        Write-Error-Custom "Failed to create AWS profile. Please configure manually."
        exit 1
    }
}

# ====== STEP 3: DETERMINE CREDENTIALS FILE PATH ======
Write-Header "Step 3: AWS Credentials File Location"

$credentialsPath = "$env:USERPROFILE\.aws\credentials"
Write-Info "AWS Credentials file location: $credentialsPath"

if (-not (Test-Path $credentialsPath)) {
    Write-Error-Custom "Credentials file not found at: $credentialsPath"
    exit 1
}

Write-Success "Credentials file found!"

# ====== STEP 4: S3 BUCKET SETUP ======
Write-Header "Step 4: S3 Bucket for Terraform State"

Write-Info "Enter S3 bucket name for remote state (default: 'wrn-demo-juice-shop'):"
$bucketName = Read-Host "S3 Bucket Name"
if ([string]::IsNullOrWhiteSpace($bucketName)) {
    $bucketName = "wrn-demo-juice-shop-$(Get-Random -Minimum 1000 -Maximum 9999)"
}

Write-Info "Checking if S3 bucket exists..."
try {
    aws s3 ls "s3://$bucketName" --profile $profileName | Out-Null
    Write-Success "S3 bucket '$bucketName' already exists!"
} catch {
    Write-Info "S3 bucket doesn't exist. Creating bucket: $bucketName"
    
    Write-Info "Enter AWS region (default: us-east-1):"
    $region = Read-Host "AWS Region"
    if ([string]::IsNullOrWhiteSpace($region)) {
        $region = "us-east-1"
    }
    
    try {
        if ($region -eq "us-east-1") {
            aws s3 mb "s3://$bucketName" --profile $profileName
        } else {
            aws s3 mb "s3://$bucketName" --region $region --create-bucket-configuration LocationConstraint=$region --profile $profileName
        }
        Write-Success "S3 bucket created: $bucketName"
    } catch {
        Write-Error-Custom "Failed to create S3 bucket. Error: $_"
        exit 1
    }
}

# ====== STEP 5: CREATE TERRAFORM.TFVARS ======
Write-Header "Step 5: Creating terraform.tfvars"

$tfvarsContent = @"
aws_profile              = "$profileName"
aws_shared_credentials_file = "$credentialsPath"
aws_bucket               = "$bucketName"
aws_region               = "$region"
"@

$tfvarsPath = Join-Path (Get-Location) "terraform.tfvars"

if (Test-Path $tfvarsPath) {
    Write-Info "terraform.tfvars already exists. Backing up to terraform.tfvars.bak"
    Copy-Item $tfvarsPath "$tfvarsPath.bak" -Force
}

$tfvarsContent | Out-File -FilePath $tfvarsPath -Encoding UTF8
Write-Success "terraform.tfvars created"
Write-Info "Location: $tfvarsPath"

# ====== STEP 6: TERRAFORM INIT ======
Write-Header "Step 6: Initializing Terraform/OpenTofu"

Write-Info "Running: $tfCommand init"
& $tfCommand init

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform init failed!"
    exit 1
}

Write-Success "Terraform initialized successfully!"

# ====== STEP 7: TERRAFORM PLAN ======
Write-Header "Step 7: Planning Deployment"

Write-Info "Running: $tfCommand plan -o=plan"
& $tfCommand plan -o=plan

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform plan failed!"
    exit 1
}

Write-Success "Terraform plan created successfully!"

# ====== STEP 8: CONFIRM DEPLOYMENT ======
Write-Header "Step 8: Ready to Deploy"

Write-Info "The following resources will be created:"
Write-Info "  - VPC (10.0.0.0/16)"
Write-Info "  - 2 Public Subnets"
Write-Info "  - Internet Gateway"
Write-Info "  - Application Load Balancer"
Write-Info "  - ECS Cluster & Service"
Write-Info "  - Juice Shop Container"
Write-Info "  - S3 Bucket for Logs"
Write-Info "  - Security Groups (Intentionally Permissive)"

Write-Info ""
Write-Info "⚠ This will create AWS resources that may incur charges!"
Write-Info "Estimated cost: ~$1-2 USD per hour while running"
Write-Info ""

$response = Read-Host "Do you want to proceed? (yes/no)"

if ($response -ne "yes") {
    Write-Error-Custom "Deployment cancelled."
    exit 0
}

# ====== STEP 9: DEPLOY ======
Write-Header "Step 9: Deploying to AWS"

Write-Info "Running: $tfCommand apply plan"
Write-Info "This may take 3-5 minutes..."

& $tfCommand apply plan

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform apply failed!"
    exit 1
}

Write-Success "Deployment completed successfully!"

# ====== STEP 10: GET OUTPUTS ======
Write-Header "Step 10: Getting Juice Shop URL"

Write-Info "Retrieving outputs..."
$output = & $tfCommand output -raw juice_shop_url

Write-Success "Deployment Complete!"
Write-Host "`n" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host "Juice Shop URL:" -ForegroundColor Green
Write-Host $output -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green

Write-Info "The Juice Shop may take 2-3 minutes to start. If you see a 503 error, wait and refresh."
Write-Info "Opening URL in default browser in 5 seconds..."

Start-Sleep -Seconds 5
Start-Process $output

# ====== CLEANUP REMINDER ======
Write-Header "Deployment Complete!"

Write-Success "Your OWASP Juice Shop is now deployed!"
Write-Info "URL: $output"
Write-Info ""
Write-Info "To access logs:"
Write-Info "  aws s3 ls s3://donald-duck --profile $profileName"
Write-Info ""
Write-Info "To destroy the infrastructure (WARNING - this is permanent):"
Write-Info "  $tfCommand destroy"
Write-Info ""
Write-Info "Next Steps:"
Write-Info "  1. Test the Juice Shop at the URL above"
Write-Info "  2. Run NMAP scans: nmap -p- $output"
Write-Info "  3. Use OWASP ZAP for vulnerability scanning"
Write-Info "  4. Ask White Rabbit Neo for pen testing suggestions"

Write-Host "`n" -ForegroundColor White
Read-Host "Press Enter to exit"
