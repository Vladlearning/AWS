#!/bin/bash

# Variables
LAMBDA_FUNCTION_NAME="CreateEC2AndInstallSoftware"
IAM_ROLE_NAME="LambdaEC2Role"
POLICY_NAME="EC2FullAccessPolicy"
ZIP_FILE="lambda_function.zip"

# Create IAM Role
echo "Creating IAM Role..."
aws iam create-role --role-name $IAM_ROLE_NAME --assume-role-policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# Attach policies to IAM Role
echo "Attaching policies to IAM Role..."
aws iam attach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

# Wait for a few seconds to allow IAM role propagation
sleep 10

# Create the Lambda function code
echo "Creating Lambda function code..."
cat << 'EOF' > lambda_function.py
import json
import boto3
import time

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    
    user_data_script = '''#!/bin/bash
    sudo apt-get update
    sudo apt-get install -y apache2
    sudo apt-get install -y software-properties-common
    sudo apt-add-repository --yes --update ppa:ansible/ansible
    sudo apt-get install -y ansible
    sudo apt-get install -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update
    sudo apt-get install -y terraform
    '''
    
    instance = ec2.run_instances(
        ImageId='ami-0c55b159cbfafe1f0',
        InstanceType='t2.micro',
        MinCount=1,
        MaxCount=1,
        KeyName='your-key-pair-name',
        SecurityGroupIds=['sg-xxxxxxxx'],
        SubnetId='subnet-xxxxxxxx',
        UserData=user_data_script,
        IamInstanceProfile={
            'Name': 'EC2InstanceProfile'
        }
    )
    
    instance_id = instance['Instances'][0]['InstanceId']
    print(f'Instance {instance_id} has been created')
    
    ec2.get_waiter('instance_running').wait(InstanceIds=[instance_id])
    
    print(f'Instance {instance_id} is now running')
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Instance {instance_id} created and initialized')
    }
EOF

# Zip the Lambda function code
echo "Zipping Lambda function code..."
zip $ZIP_FILE lambda_function.py

# Create the Lambda function
echo "Creating Lambda function..."
aws lambda create-function --function-name $LAMBDA_FUNCTION_NAME \
  --runtime python3.8 \
  --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$IAM_ROLE_NAME \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://$ZIP_FILE

# Clean up
echo "Cleaning up..."
rm lambda_function.py
rm $ZIP_FILE

echo "Done. The Lambda function $LAMBDA_FUNCTION_NAME has been created."
