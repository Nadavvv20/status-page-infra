param(
  [string]$Tag = $("ci-{0}" -f (Get-Date -UFormat %s))
)

$ValuesFile = "helm-statuspage\values.yaml"
$Branch = "CI/CD"

if (-not (Test-Path $ValuesFile)) {
  Write-Error "values file not found: $ValuesFile"
  exit 1
}

Write-Host "Updating image.tag to '$Tag' in $ValuesFile"
(Get-Content $ValuesFile) -replace 'tag: "[^"]*"', "tag: \"$Tag\"" | Set-Content $ValuesFile

Write-Host "Committing and pushing to branch $Branch"
git fetch origin
git checkout -B $Branch
git add $ValuesFile
try {
  git commit -m "Update image tag to $Tag [ci skip]"
  git push --set-upstream origin $Branch
  Write-Host "Pushed branch $Branch with updated tag: $Tag"
} catch {
  Write-Host "No changes to commit or push failed: $_"
}

Write-Host "Done. Watch GitHub Actions for runs triggered by this push."
