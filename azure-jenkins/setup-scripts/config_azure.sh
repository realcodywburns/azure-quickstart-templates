#!/bin/sh
log_dir_path='/tmp/azurejenkinslog/'
if [ ! -d $log_dir_path ]
then
    sudo mkdir $log_dir_path
fi

log_file_name="config_storage.log"
log_file_path="$log_dir_path$log_file_name"

if [ ! -f $log_file_path ]
then
    sudo touch $log_file_path
fi

# ip_addr=$(ip route get 8.8.8.8 | awk '/8.8.8.8/ {print $NF}')
instruction_goto_dashboard="Please go to Jenkins dashboard by inputting <Your VM IP address>:8080 in your preferred browser. You can find the IP address in Azure portal."

dest_account_file_path='/var/lib/jenkins/com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher.xml'

echo "Usage:
  1 sh config_storage.sh
  2 sh config_storage.sh <Subscription ID>
  3 sh config_storage.sh <Subscription ID> <Storage Account name>
  4 sh config_storage.sh <Subscription ID> <Storage Account name> <Resource Group name>
  5 sh config_storage.sh <Subscription ID> <Storage Account name> <Resource Group name> <Source Container name> <Dest Container name>
"

SUBSCRIPTION_ID=$1
STORAGE_ACCOUNT_NAME=$2
RESOURCE_GROUP_NAME=$3
SOURCE_CONTAINER_NAME=$4
DEST_CONTAINER_NAME=$5

sudo sh -c "echo '$(date): Login to Azure' >> $log_file_path"
azure login
if [ ! -z "$SUBSCRIPTION_ID" ]
then
    sudo sh -c "echo '$(date): Set subscription ID' >> $log_file_path"
    azure account set $SUBSCRIPTION_ID
else
    sudo sh -c "echo '$(date): List Azure subscriptions' >> $log_file_path"
    subscriptions_list=`azure account list --json`
    subscriptions_list_count=`echo $subscriptions_list | jq '. | length'`
    if [ $subscriptions_list_count -eq 0 ]
    then
        sudo sh -c "echo '$(date): No subscription found' >> $log_file_path"
        echo "You need to sign up an Azure Subscription here: https://azure.microsoft.com"
        exit 1
    else
        subscription_index=0
        if [ $subscriptions_list_count -gt 1 ]
        then
            sudo sh -c "echo '$(date): Multiple subscriptions found' >> $log_file_path"
            echo $subscriptions_list | jq -r 'keys[] as $i | "\($i), \(.[$i] | .name)"'
            echo "Select a subscription for Azure storage plugin by typing an index number from above list and press [Enter]."
            read subscription_index
        fi
        SUBSCRIPTION_ID=`echo $subscriptions_list | jq -r '.['$subscription_index'] | .id'`
    fi
    sudo sh -c "echo '$(date): Set subscription ID' >> $log_file_path"
    azure account set $SUBSCRIPTION_ID
fi

if [ -z "$STORAGE_ACCOUNT_NAME" ]
then
    sudo sh -c "echo '$(date): List storage accounts' >> $log_file_path"
    storage_account_list=`azure storage account list --json`
    storage_account_list_length=`echo $storage_account_list | jq '. | length'`
    if [ $storage_account_list_length -eq 0 ]
    then
        sudo sh -c "echo '$(date): No storage accounts found' >> $log_file_path"
        echo "Please go to Azure portal and create a storage account."
        exit 1
    else
        storage_account_index=0
        if [ $storage_account_list_length -gt 1 ]
        then
            sudo sh -c "echo '$(date): List storage accounts for selection' >> $log_file_path"
            echo $storage_account_list | jq -r 'keys[] as $i | "\($i), \(.[$i] | .name)"'
            echo "Select a storage account by typing an index number from above list and press [Enter]."
            read storage_account_index
        fi

        sudo sh -c "echo '$(date): Set storage account' >> $log_file_path"
        STORAGE_ACCOUNT_NAME=`echo $storage_account_list | jq -r '.['$storage_account_index'] | .name'`
        RESOURCE_GROUP_NAME=`echo $storage_account_list | jq -r '.['$storage_account_index'] | .resourceGroup'`
    fi
fi

sudo sh -c "echo '$(date): Get storage account key' >> $log_file_path"
keys_result=`azure storage account keys list $STORAGE_ACCOUNT_NAME -g $RESOURCE_GROUP_NAME --json`
STORAGE_ACCOUNT_KEY=`echo $keys_result | jq -r '.[0].value'`

# Creat config file for adding storage account
tmp_account_file_path='/tmp/com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher.xml'

sudo sh -c "echo '$(date): Create temp storage account config file' >> $log_file_path"

cat <<EOF > $tmp_account_file_path
<?xml version='1.0' encoding='UTF-8'?>
<com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher_-WAStorageDescriptor plugin="windows-azure-storage@0.3.1">
  <storageAccounts>
    <com.microsoftopentechnologies.windowsazurestorage.beans.StorageAccountInfo>
      <storageAccName>${STORAGE_ACCOUNT_NAME}</storageAccName>
      <storageAccountKey>${STORAGE_ACCOUNT_KEY}</storageAccountKey>
      <blobEndPointURL>http://blob.core.windows.net/</blobEndPointURL>
    </com.microsoftopentechnologies.windowsazurestorage.beans.StorageAccountInfo>
  </storageAccounts>
</com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher_-WAStorageDescriptor>
EOF

sudo sh -c "echo '$(date): Copy temp config file to Jenkins directory' >> $log_file_path"
sudo cp $tmp_account_file_path $dest_account_file_path
echo "Storage account was successfully added to Jenkins Azure Storage plugin."

dest_download_container_file_path='/var/lib/jenkins/jobs/1. Download Dependencies. Invoked by pipeline/config.xml'
dest_upload_container_file_path='/var/lib/jenkins/jobs/3. Upload test app. Invoked by pipeline/config.xml'
if [ -f "$dest_download_container_file_path" ] && [ -f "$dest_upload_container_file_path" ]
then
    echo "Blob containers have been set before.\n$instruction_goto_dashboard"
    exit 0
fi

sudo sh -c "echo '$(date): Set container config files' >> $log_file_path"
# Create config file for adding source and dest containers
if [ -z "$SOURCE_CONTAINER_NAME" ] || [ -z "$DEST_CONTAINER_NAME" ]
then
    container_list=`azure storage container list -a $STORAGE_ACCOUNT_NAME -k $STORAGE_ACCOUNT_KEY --json`
    container_list_length=`echo $container_list | jq '. | length'`
    if [ $container_list_length -eq 0 ]
    then
        echo "You don't have any existing containers now. You can go to Azure portal or use Microsoft Azure Storage Explorer to create one."
    elif [ $container_list_length -eq 1 ]
    then
        SOURCE_CONTAINER_NAME=`echo $container_list | jq -r '.['$container_index'] | .name'`
        DEST_CONTAINER_NAME=$SOURCE_CONTAINER_NAME
    else
        echo $container_list | jq -r 'keys[] as $i | "\($i), \(.[$i] | .name)"'
        echo "Select the source container by typing an index number from above list and press [Enter]."
        read container_index
        SOURCE_CONTAINER_NAME=`echo $container_list | jq -r '.['$container_index'] | .name'`

        echo "Select the destination container by typing an index number from above list and press [Enter]."
        read container_index
        DEST_CONTAINER_NAME=`echo $container_list | jq -r '.['$container_index'] | .name'`
    fi
fi

sudo sh -c "echo '$(date): Create temp source container config file' >> $log_file_path"
# Creat config file for adding SOURCE container
tmp_download_container_file_path='/tmp/source_config.xml'
cat <<EOF > $tmp_download_container_file_path
<?xml version='1.0' encoding='UTF-8'?>
<project>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <com.microsoftopentechnologies.windowsazurestorage.AzureStorageBuilder plugin="windows-azure-storage@0.3.1">
      <storageAccName>${STORAGE_ACCOUNT_NAME}</storageAccName>
      <containerName>${SOURCE_CONTAINER_NAME}</containerName>
      <includeFilesPattern>**/*.*</includeFilesPattern>
      <excludeFilesPattern></excludeFilesPattern>
      <downloadDirLoc>\${BUILD_ID}</downloadDirLoc>
      <flattenDirectories>false</flattenDirectories>
      <includeArchiveZips>false</includeArchiveZips>
    </com.microsoftopentechnologies.windowsazurestorage.AzureStorageBuilder>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF

sudo sh -c "echo '$(date): Copy temp source config file to Jenkins directory' >> $log_file_path"
sudo cp $tmp_download_container_file_path "$dest_download_container_file_path"
echo "Blob container with name $SOURCE_CONTAINER_NAME was successfully set as the download source."

sudo sh -c "echo '$(date): Create temp dest container config file' >> $log_file_path"
# Create config file for adding DEST container
tmp_upload_container_file_path='/tmp/dest_config.xml'
cat <<EOF > $tmp_upload_container_file_path
<?xml version='1.0' encoding='UTF-8'?>
<project>
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>if [ ! -d &quot;text&quot; ]; then
  mkdir text
fi

cd text
echo &quot;Hello Azure Storage from Jenkins&quot; &gt; hello.txt
date &gt; date.txt</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers>
    <com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher plugin="windows-azure-storage@0.3.1">
      <storageAccName>${STORAGE_ACCOUNT_NAME}</storageAccName>
      <containerName>${DEST_CONTAINER_NAME}</containerName>
      <cntPubAccess>false</cntPubAccess>
      <cleanUpContainer>false</cleanUpContainer>
      <allowAnonymousAccess>false</allowAnonymousAccess>
      <uploadArtifactsOnlyIfSuccessful>false</uploadArtifactsOnlyIfSuccessful>
      <doNotFailIfArchivingReturnsNothing>false</doNotFailIfArchivingReturnsNothing>
      <uploadZips>false</uploadZips>
      <doNotUploadIndividualFiles>false</doNotUploadIndividualFiles>
      <filesPath>text/*.txt</filesPath>
      <excludeFilesPath></excludeFilesPath>
      <virtualPath>\${JOB_NAME}/\${BUILD_ID}</virtualPath>
    </com.microsoftopentechnologies.windowsazurestorage.WAStoragePublisher>
  </publishers>
  <buildWrappers/>
</project>
EOF

sudo sh -c "echo '$(date): Copy temp dest container config file to Jenkins directory' >> $log_file_path"
sudo cp $tmp_upload_container_file_path "$dest_upload_container_file_path"
echo "Blob container with name $DEST_CONTAINER_NAME was successfully set as the upload destination."

echo "Storage account and containers are all set successfully.\n$instruction_goto_dashboard"

sudo sh -c "echo '$(date): Restart Jenkins' >> $log_file_path"
# Restart Jenkins
sudo service jenkins restart

# Set service principal

echo "In order to use Jenkins with Azure slave plugin or web app you first create a service principal for Jenkins to run as and also to manage your azure subscription."
echo "Background article: https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/#authenticate-with-password---azure-cli"
echo "Execute the following commands:"
echo "    azure login"
echo "    azure config mode arm"
echo "    azure account show"
echo "From above record the 'data: ID' and 'data: Tenant ID' - these will be your subscription ID and tenant ID"
echo " "
echo "Create your application in Azure AD"
echo "    azure ad app create --name 'exampleapp' --home-page 'https://www.contoso.org' --identifier-uris 'https://www.contoso.org/example' --password <Your_Password>"
echo "From above record the 'data: AppId' - this will be your client ID while the password that was set will be the AppKey"
echo " "
echo "Create service principal"
echo "    azure ad sp create <AppId from previous step>"
echo " "
echo "Assign rights to service principal"
echo "    azure role assignment create --objectId <Object ID from above step> -o Owner -c /subscriptions/{subscriptionId from above step}/"
echo " "
echo " "

my_app_name_uuid=$(python -c 'import uuid; print str(uuid.uuid4())[:8]')
MY_APP_NAME="app${my_app_name_uuid}"

MY_APP_KEY=$(python -c 'import uuid; print uuid.uuid4().hex')

my_app_id_URI="${MY_APP_NAME}_id"

if [ $subscriptions_list_count -eq 0 ]
then
    echo "You need to sign up an Azure Subscription here: https://azure.microsoft.com"
    exit 1
elif [ $subscriptions_list_count -gt 1 ]
then
    echo $subscriptions_list | jq -r 'keys[] as $i | "\($i), \(.[$i] | .name)"'
    echo "Select a subscription for service principal by typing an index number from above list and press [Enter]."
    read subscription_index
    subscription_id=`echo $subscriptions_list | jq -r '.['$subscription_index'] | .id'`
    azure account set $subscription_id
fi

MY_SUBSCRIPTION_ID=$(azure account show --json | jq -r '.[0].id')
MY_TENANT_ID=$(azure account show --json | jq -r '.[0].tenantId')

azure config mode arm

my_error_check=$(azure ad sp show --search $MY_APP_NAME --json | grep "displayName" | grep -c \"$MY_APP_NAME\" )

if [ $my_error_check -gt 0 ];
then
  echo " "
  echo "Found an app id matching the one we are trying to create; we will reuse that instead"
else
  echo " "
  echo "Creating application in active directory:"
  echo "azure ad app create --name '$MY_APP_NAME' --home-page 'http://$MY_APP_NAME' --identifier-uris 'http://$my_app_id_URI/' --password $MY_APP_KEY"
  azure ad app create --name $MY_APP_NAME --home-page http://$MY_APP_NAME --identifier-uris http://$my_app_id_URI/ --password $MY_APP_KEY
  # Give time for operation to complete
  echo "Waiting for operation to complete...."
  sleep 20
  my_error_check=$(azure ad app show --search $MY_APP_NAME --json | grep "displayName" | grep -c \"$MY_APP_NAME\" )

  if [ $my_error_check -gt 0 ];
  then
    my_app_object_id=$(azure ad app show --json --search $MY_APP_NAME | jq -r '.[0].objectId')
    MY_CLIENT_ID=$(azure ad app show --json --search $MY_APP_NAME | jq -r '.[0].appId')
    echo " "
    echo "Creating the service principal in AD"
    echo "azure ad sp create -a $MY_CLIENT_ID"
    azure ad sp create -a $MY_CLIENT_ID
    # Give time for operation to complete
    echo "Waiting for operation to complete...."
    sleep 20
    my_app_sp_object_id=$(azure ad sp show --search $MY_APP_NAME --json | jq -r '.[0].objectId')

    echo "Assign rights to service principle"
    echo "azure role assignment create --objectId $my_app_sp_object_id -o Owner -c /subscriptions/$MY_SUBSCRIPTION_ID"
    azure role assignment create --objectId $my_app_sp_object_id -o Owner -c /subscriptions/$MY_SUBSCRIPTION_ID
  else
    echo " "
    echo "We've encounter an unexpected error; please hit Ctr-C and retry from the beginning"
    read my_error
  fi
fi

MY_CLIENT_ID=$(azure ad sp show --search $MY_APP_NAME --json | jq -r '.[0].appId')

echo " "
echo "Subscription ID:" $MY_SUBSCRIPTION_ID
echo "Tenant ID:" $MY_TENANT_ID
echo "Client ID:" $MY_CLIENT_ID
echo "Client Secret:" $MY_APP_KEY
echo "OAuth 2.0 Token Endpoint:" "https://login.microsoftonline.com/${MY_TENANT_ID}/oauth2/token"
echo " "
echo "You can verify the service principal was created properly by running:"
echo "azure login -u "$MY_CLIENT_ID" --service-principal --tenant $MY_TENANT_ID"
echo " "
