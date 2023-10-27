#!/bin/sh

#ami="ami-002073a635b67b824" # earthly AMI
ami=ami-0e0f3d4588f992288 # Public Amazon Linux 2
sg=sg-0d84501f426528483 # Security group with HTTP access to port 80.

aws ec2 run-instances \
   --image-id "$ami" \
   --count 1 \
   --instance-type t3.medium \
   --security-group-ids "$sg" \
   --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-debugging}]' \
   --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":18,\"DeleteOnTermination\":true, \"Encrypted\": true}}]" \
   --hibernation-options "{\"Configured\": true}" \
   --user-data file://user_data.yaml \
   > output.json

instanceID="$(cat output.json | jq -r '.Instances[0].InstanceId')"
echo "Launched new instance: $instanceID"



while true; do

  echo ""
  for i in {1..10}; do
    ip="$(aws ec2 describe-instances --instance-id $instanceID | jq -r '.Reservations[0].Instances[0].PublicIpAddress')"
    if [ "$ip" != "null" ]; then
      echo "Public IP: $ip"
      break
    fi
  done
  
  echo "Waiting for web server to answer..."
  for i in {1..300}; do
    if curl -s "http://$ip"; then
      echo "server online"
      online=1
      break
    fi
    if [[ $i = 300 ]]; then
      echo "instance did not start in 5 mins - may have corrupted filesystem"
      exit 1
    fi
    sleep 1
  done

  echo "web server answered"
  echo "stopping instance..."
  aws ec2 stop-instances --instance-ids "$instanceID" > /dev/null
  for i in {1..300}; do
    state="$(aws ec2 describe-instances --instance-id "$instanceID" | jq -r '.Reservations[0].Instances[0].State.Name')"
    if [ "$state" = "stopped" ]; then
      echo "instance finished stopping"
      echo "starting instance again..."
      aws ec2 start-instances --instance-ids "$instanceID" > /dev/null
      break
    fi
    sleep 2
  done

done
