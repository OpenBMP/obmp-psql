# Building OpenBMP PostgreSQL Consumer

Dependencies
------------
- Java 1.8 or greater
- Maven 3.x or greater
- Python psycopg2-binary
- DNS Python
 
#### Example: Install depends on Ubuntu 16.04:
    sudo apt-get install git openjdk-9-jdk git openjdk-9-jre-headless maven
    sudo pip install psycopg2-binary
    sudo pip install dnspython
    

Build
-----
You can build from source using maven as below:


### (1) Install openbmp-java-api-message
    
    git clone https://github.com/OpenBMP/openbmp-java-api-message.git
    cd openbmp-java-api-message
    mvn clean install

### (2) Build obmp-psql

    cd ../
    git clone https://github.com/OpenBMP/obmp-psql.git
    cd obmp-psql
    mvn clean package
    
> The above will create a JAR file under **target/**.  The JAR file is the complete package, which includes the dependancies. 

Install
-------
