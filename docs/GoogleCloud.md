
# Google GKE Setup

Use the gke image
`
ghcr.io/dataaxiom/tiecd:latest-gke
`

Setup IAM Service Account for Pipeline Use

https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication


## Create IAM service account
`
$ gcloud iam service-accounts create ci-cd-pipeline
`

## Grant IAM service account cluster access
`
$ gcloud projects add-iam-policy-binding PROJECT_ID --member=serviceAccount:ci-cd-pipeline@PROJECT_ID.iam.gserviceaccount.com  --role=roles/container.developer
`

## Create and download key for the IAM service account

`
$ gcloud iam service-accounts keys create gsa-key.json --iam-account=ci-cd-pipeline@PROJECT_ID.iam.gserviceaccount.com
`

# Use IAM Service Account from TieCD

## Sample Environment for tie.yml
```
environments:
- name: prod
  apiType: kubernetes
  apiProvider: gke
  projectId: my-project
  zone: us-west3
  serviceAccountName: ci-cd-pipeline
  apiClientKey: ${GKE_KEY}
#  apiClientKeyFile: gke.json
```
