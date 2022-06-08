@echo off

set DEFAULT_APP=demo-excel-calculator

mvn archetype:generate -DgroupId=com.foo -DartifactId=%DEFAULT_APP% -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false -DarchetypeCatalog=local
