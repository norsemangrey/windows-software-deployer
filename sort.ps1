function Get-ClonedObject {

    param($DeepCopyObject)

    $memStream = new-object IO.MemoryStream
    $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $formatter.Serialize($memStream,$DeepCopyObject)
    $memStream.Position=0
    $formatter.Deserialize($memStream)

}

function Get-TopologicalSort {
    param(
        [PSObject] $objectsToSort,
        [string]$sortProperty,
        [string]$dependenciesProperty
    )

    # Handle cases where there are fewer than two objects
    if ($objectsToSort.Count -lt 2) {

        if ($objectsToSort.Count -eq 1) {

            # Set Sort property to 0 for the single item
            $objectsToSort[0] | Add-Member -MemberType NoteProperty -Name 'Sort' -Value 0 -Force

        }

        # Return the array (either with one item or empty) as-is
        return $objectsToSort

    }

    if ( $localDebug ) { Write-Host "Sorting objects based on inter-dependencies ..." }

    # Initialize list for original unsorted key-value list
    $originalObjectList = @{}

    # Get desired keys and dependency values to sort by
    forEach ($object in $objectsToSort) {

        # Assuming each object has a unique key that we want to use for the hashtable
        $key = $object.$sortProperty
        $value = $object.$dependenciesProperty

        # Add key-value pair to the hashtable
        $originalObjectList[$key] = $value
    }

    # Make sure we can use HashSet
    Add-Type -AssemblyName System.Core

    # Clone it so as to not alter original
    $currentObjectList = [hashtable] (Get-ClonedObject $originalObjectList)

    # Initialize list for sorted object identifiers
    $topologicallySortedObjects = New-Object System.Collections.ArrayList

    # Initialize a queue list for checked objects
    $objectsWithNoUnCheckedDependencies = New-Object System.Collections.Queue

    # Initialize a list for object list and dependencies converted to HashSets
    $fasterObjectList = @{}

    # Keep track of all nodes in case they put it in as an edge destination but not source
    $allObjects = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentObjectList.Keys)

    #
    forEach( $currentObject in $currentObjectList.Keys ) {

        # Get dependencies of the current object
        $currentObjectDependencies = [array] $currentObjectList[$currentObject]

        # Check if there are any dependencies
        if( $currentObjectDependencies.Length -eq 0 ) {

            # Add to end of list of objects with no dependencies
            $objectsWithNoUnCheckedDependencies.Enqueue($currentObject)

        }

        # Adds dependency as an object if it does not exist
        forEach ( $currentObjectDependency in $currentObjectDependencies ) {

            # Check if dependency is listed as an object
            if( !$allObjects.Contains( $currentObjectDependency ) ) {

                # Add dependency to list of objects
                [void] $allObjects.Add($currentObjectDependency)

            }
        }

        # Create a HashSet from current dependencies
        $currentObjectDependencies = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentObjectDependencies )

        # Add current object and dependencies to a new list for faster operation
        [void] $fasterObjectList.Add($currentObject, $currentObjectDependencies)

    }

    # Reconcile by adding dependencies with no parent object as objects with no children in the object list
    forEach ( $currentObject in $allObjects ) {

        # Check if object is in the current object list
        if( !$currentObjectList.ContainsKey($currentObject) ) {

            # Add as new object in the list
            [void] $currentObjectList.Add($currentObject, (New-Object -TypeName System.Collections.Generic.HashSet[object]))

            # Add also to list of objects with no dependencies
            $objectsWithNoUnCheckedDependencies.Enqueue($currentObject)

        }
    }

    # Get the complete "faster" object list
    $currentObjectList = $fasterObjectList

    # Cross-reference all project dependencies to find any cyclic dependencies
    forEach ( $referenceObject in $currentObjectList.Keys ) {

        # Check each object against every other object except itself
        forEach ( $checkedObject in $currentObjectList.Keys | Where-Object { $_ -ne $referenceObject } ) {

            # Check if object if dependent on reference object
            if ( $currentObjectList[$checkedObject].Contains($referenceObject) ) {

                # Check for a reciprocal dependency and exit if found
                if ( $currentObjectList[$referenceObject].Contains($checkedObject) ) {

                    # Set an error message and exit the loop
                    $errorMessage = "Error: Cyclic Dependency ( {0} <-> {1} )" -f
                    $referenceObject,
                    $checkedObject

                    Write-Error $errorMessage

                    return $False

                }

            }

        }

    }

    # Do a topological sort by using Kahn's algorithm
    while( $objectsWithNoUnCheckedDependencies.Count -gt 0 ) {

        # Get first object with no un-processed dependencies
        $processedObject = $objectsWithNoUnCheckedDependencies.Dequeue()

        # Remove object from current object list
        [void] $currentObjectList.Remove($processedObject)

        # Add to end of sorted object list
        [void] $topologicallySortedObjects.Add($processedObject)

        # Check if the processed object is a dependency for any other object
        forEach( $currentUnProcessedObject in $currentObjectList.Keys ) {

            # Get the dependencies of the currently checked unprocessed object
            $currentUnProcessedObjectDependencies = $currentObjectList[$currentUnProcessedObject]

            # Check if any dependency is the processed object
            if( $currentUnProcessedObjectDependencies.Contains($processedObject) ) {

                # Remove the dependency reference to the processed object
                [void] $currentUnProcessedObjectDependencies.Remove($processedObject)

                # Check if the current un-processed object has any more dependencies
                if( $currentUnProcessedObjectDependencies.Count -eq 0 ) {

                    # Add the object to the list of objects with no un-checked dependencies
                    [void] $objectsWithNoUnCheckedDependencies.Enqueue($currentUnProcessedObject)

                }
            }
        }
    }

    # Sort provided list of objects according to the topological sorted list
    $sortedObjects = $objectsToSort | Sort-Object { $topologicallySortedObjects.IndexOf($_.$sortProperty) }

    $sortedObjects = $sortedObjects | ForEach-Object {
        if ($_.PSObject.Properties.Match('Sort').Count -gt 0) {

            # If the Sort property exists, update it
            $_.Sort = $sortedObjects.IndexOf($_)

        } else {

            # Otherwise, add Sort as a new property
            $_ | Add-Member -MemberType NoteProperty -Name 'Sort' -Value $sortedObjects.IndexOf($_)

        }

        $_

    }

    # Return sorted objects
    return $sortedObjects

}

$localDebug = $global:debug