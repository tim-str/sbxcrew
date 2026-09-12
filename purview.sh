export TENANT='9d16d3ac-f3d7-4546-a83a-12648058f620'
export CLIENT='81abd9e1-3f0c-404b-8174-d93e4f112db2'
// required to export SCRT

export ENDPOINT='https://9d16d3ac-f3d7-4546-a83a-12648058f620-api.purview-service.microsoft.com'

export BASE="$ENDPOINT/datamap/api/atlas/v2"
export AV="api-version=2023-09-01"

TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT" \
  -d "client_secret=$SECRET" \
  -d "scope=https://purview.azure.net/.default" | jq -r .access_token)

echo "${TOKEN:0:20}..."

curl -s -H "Authorization: Bearer $TOKEN" "$ENDPOINT/catalog/api/atlas/v2/types/typedefs" | jq '.entityDefs | length'

curl -s -G -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/datamap/api/atlas/v2/entity/uniqueAttribute/type/azure_blob_path" \
  --data-urlencode "attr:qualifiedName=https://pvwdevdata.blob.core.windows.net/raw/employees.csv" \
  --data-urlencode "api-version=2023-09-01" \
  | jq '{classifications: [.entity.classifications[]?.typeName],
         relationships: (.entity.relationshipAttributes | keys)}'

curl -s -G -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/datamap/api/atlas/v2/entity/guid/3ec93105-ba37-4603-afeb-72f6f6f60000" \
  --data-urlencode "api-version=2023-09-01" \
  | jq '{type: .entity.typeName,
         qn: .entity.attributes.qualifiedName,
         rels: (.entity.relationshipAttributes | keys),
         referred: (.referredEntities | length)}'

curl -s -G -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/datamap/api/atlas/v2/entity/guid/3ec93105-ba37-4603-afeb-72f6f6f60000" \
  --data-urlencode "api-version=2023-09-01" \
  | jq -r '.referredEntities | to_entries[] |
      "\(.value.attributes.name)\t\([.value.classifications[]?.typeName] | join(", "))"'

curl -s -G -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/datamap/api/atlas/v2/entity/guid/3ec93105-ba37-4603-afeb-72f6f6f60000" \
  --data-urlencode "api-version=2023-09-01" \
  | jq '.referredEntities | to_entries[] | select(.value.attributes.name=="bank_account_number") | .value.classifications'


