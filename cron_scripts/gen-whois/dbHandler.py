# Connection handle
conn=""

# Cursor handle
cursor=""

# Last query time in seconds (floating point)
last_query_time=0

# Connect to database
connectDb() {
    local user=$1
    local pw=$2
    local host=$3
    local database=$4

    # Connect to the database
    conn=$(psql -U "$user" -W "$pw" -h "$host" -d "$database" 2>&1)

    # Check if the connection was successful
    if [[ "$conn" == *"psql: FATAL:"* ]]; then
        echo "ERROR: Connect failed: $conn"
        exit 1
    fi

    # Create a cursor
    cursor=$(psql -U "$user" -W "$pw" -h "$host" -d "$database" -c "" 2>&1)

    # Check if the cursor was created successfully
    if [[ "$cursor" == *"psql: FATAL:"* ]]; then
        echo "ERROR: Failed to create cursor: $cursor"
        exit 1
    fi
}

# Close the database connection
close() {
    # Close the cursor
    if [[ -n "$cursor" ]]; then
        psql -c "" "$cursor" >/dev/null 2>&1
        cursor=""
    fi

    # Close the connection
    if [[ -n "$conn" ]]; then
        psql -c "" "$conn" >/dev/null 2>&1
        conn=""
    fi
}

# Create table schema
createTable() {
    local tableName=$1
    local tableSchema=$2
    local dropIfExists=$3

    # Check if the cursor is available
    if [[ -z "$cursor" ]]; then
        echo "ERROR: Looks like psql is not connected, try to reconnect."
        return 1
    fi

    # Drop the table if it exists
    if [[ "$dropIfExists" == "true" ]]; then
        psql -c "DROP TABLE IF EXISTS $tableName" "$cursor" >/dev/null 2>&1
    fi

    # Create the table
    psql -c "$tableSchema" "$cursor" >/dev/null 2>&1

    # Check if the table was created successfully
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to create table"
        return 1
    fi

    return 0
}

# Run a query and return the result set back
#  arg query:       The query to run - should be a working SELECT statement
#  arg queryParams: Dictionary of parameters to supply to the query for
#                   variable substitution
#  return:          Returns "1" if error, otherwise array list of rows
query() {
    local query=$1
    local queryParams=$2

    # Check if the cursor is available
    if [[ -z "$cursor" ]]; then
        echo "ERROR: Looks like psql is not connected, try to reconnect"
        return 1
    fi

    # Execute the query
    local startTime=$(date +%s.%N)
    if [[ -n "$queryParams" ]]; then
        psql -c "$(printf "$query" "$queryParams")" "$cursor" >/dev/null 2>&1
    else
        psql -c "$query" "$cursor" >/dev/null 2>&1
    fi
    local endTime=$(date +%s.%N)

    # Calculate the query execution time
    last_query_time=$(echo "$endTime - $startTime" | bc -l)

    # Fetch the query results
    local rows=$(psql -c "FETCH 10000 FROM $cursor" "$cursor" 2>/dev/null)

    # Check if there are more rows to fetch
    while [[ -n "$rows" ]]; do
        echo "$rows"
        rows=$(psql -c "FETCH 10000 FROM $cursor" "$cursor" 2>/dev/null)
    done

    return 0
}

# Runs a query that would normally not have any results, such as insert, update, delete
#  arg query:       The query to run - should be a working INSERT or UPDATE statement
#  arg queryParams: Dictionary of parameters to supply to the query for
#                   variable substitution
#  return:          Returns "0" if successful, "1" if not
queryNoResults() {
    local query=$1
    local queryParams=$2

    # Check if the cursor is available
    if [[ -z "$cursor" ]]; then
        echo "ERROR: Looks like psql is not connected, try to reconnect"
        return 1
    fi

    # Execute the query
    local startTime=$(date +%s.%N)
    if [[ -n "$queryParams" ]]; then
        psql -c "$(printf "$query" "$queryParams")" "$cursor" >/dev/null 2>&1
    else
        psql -c "$query" "$cursor" >/dev/null 2>&1
    fi
    local endTime=$(date +%s.%N)

    # Calculate the query execution time
    last_query_time=$(($endTime - $startTime))

    return 0
}
