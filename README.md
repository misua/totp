# AWS Infrastructure POC with Bastion Host and TOTP Authentication

This project sets up a proof-of-concept (POC) AWS infrastructure using Terraform. It includes a bastion host with Google Authenticator for two-factor authentication (2FA), a NAT instance for internet access from private subnets, and a private EC2 instance running a simple NGINX 'Hello' demo.

## Prerequisites

- **Terraform**: Ensure Terraform is installed on your system. Download it from [terraform.io](https://www.terraform.io/downloads.html) if needed.
- **AWS Credentials**: Configure your AWS credentials using the AWS CLI or environment variables. Ensure you have an IAM user with permissions to create VPCs, subnets, EC2 instances, and security groups.
- **SSH Key Pair**: Ensure you have an SSH key pair named 'aws-key' registered in AWS. This key is used to access the EC2 instances.

## Deployment Instructions for First-Time Users

1. **Clone or Navigate to Project Directory**:
   Open your terminal and navigate to this project directory (`/home/charles.pino/Desktop/totp`).

2. **Initialize Terraform**:
   Run the following command to initialize Terraform and download the necessary providers:
   ```bash
   terraform init
   ```

3. **Review the Infrastructure Plan**:
   Check the resources Terraform will create by running:
   ```bash
   terraform plan
   ```
   Review the output to ensure it matches your expectations (VPC, subnets, bastion host, NAT instance, NGINX EC2 instance).

4. **Deploy the Infrastructure**:
   Deploy the AWS infrastructure by running:
   ```bash
   terraform apply
   ```
   Type `yes` when prompted to confirm the deployment. This process may take a few minutes.

5. **Note the Outputs**:
   After deployment, Terraform will display outputs including the public IP of the bastion host (`bastion_public_ip`), the public IP of the NAT instance (`nat_public_ip`), and the private IP of the NGINX instance (`nginx_private_ip`). Save these for reference.

## Accessing the Bastion Host with TOTP Authentication

1. **SSH into the Bastion Host**:
   Use the public IP of the bastion host from the Terraform output to SSH as the `ec2-user`:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ec2-user@<bastion_public_ip>
   ```
   Replace `<bastion_public_ip>` with the actual IP address from the output.

2. **Set Up Google Authenticator**:
   - On your first login, you will be prompted to set up Google Authenticator for 2FA.
   - Follow the on-screen instructions to scan the displayed QR code with the Google Authenticator app on your smartphone.
   - Answer the setup questions as prompted (e.g., make codes time-based, update recovery codes).
   - Save the provided emergency scratch codes in a secure place; these are needed if you lose access to your app.

3. **Subsequent Logins**:
   After setup, every SSH login to the bastion host will prompt for a verification code. Open the Google Authenticator app on your phone, enter the current 6-digit code for this bastion host, and input it when prompted.

## Accessing the NGINX Demo Instance

1. **From the Bastion Host**:
   Once logged into the bastion host, you can SSH into the private NGINX instance using its private IP (from Terraform output `nginx_private_ip`):
   ```bash
   ssh -i ~/.ssh/id_ed25519 ec2-user@<nginx_private_ip>
   ```
   Replace `<nginx_private_ip>` with the actual IP address from the output.

2. **Verify NGINX Demo**:
   On the NGINX instance, check if the service is running:
   ```bash
   curl http://localhost
   ```
   You should see a simple 'Hello from NGINX!' HTML page response.

## Important Post-Deployment Step: Configure NAT Instance Routing

Due to limitations in the current AWS Terraform provider, direct routing to the NAT instance cannot be set automatically. You must manually update the private subnet's route table after deployment:

1. Log in to the AWS Management Console.
2. Navigate to **VPC** > **Route Tables**.
3. Find the route table tagged as `private-rt` (associated with the private subnet).
4. Edit the route for `0.0.0.0/0`:
   - Remove the current gateway (internet gateway placeholder).
   - Set the target to the Elastic Network Interface (ENI) of the NAT instance (find the NAT instance in EC2, note its primary network interface).
5. Save the changes.

This step ensures that the private NGINX instance can access the internet through the NAT instance for updates or external requests.

## Troubleshooting

- **SSH Connection Issues**: Ensure your SSH key (`aws-key` in AWS) matches the private key you're using locally. Check security group rules if connections are blocked.
- **TOTP Setup Problems**: If you can't scan the QR code, ensure your terminal supports graphical output or check `/home/ec2-user/authenticator_instructions.txt` on the bastion host for manual setup instructions.
- **NGINX Not Responding**: Verify the instance is running on the bastion host SSH session and check security group rules for port 80 access from the public subnet.

## Destroying the Infrastructure

When you're done with the POC, destroy the infrastructure to avoid unnecessary AWS charges:
```bash
terraform destroy
```
Type `yes` when prompted to confirm.
