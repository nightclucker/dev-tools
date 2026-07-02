# New P4 Project Setup Script File Project using Claude



### Objective

Create a shell script that can be easily run locally or used to automate, from such a tool like Jenkins, the creation of a new project in Perforce (P4).



### Final Product

* Shell script or something similar that can be run on Mac and Linux.
* Must create a depot with several streams.
* Must create a p4 group with users.
* Group must have permissions for the users.



### Main Features

* Creates a new depot.
* Create a Main, ArtTools, and Tools mainline streams
* Create a release flow from Main by way of Main <-> Staging -> Production or Release -> Live
* Release streams do not inherit from parent with the exception of the staging stream.
* Create a group to add users to give them access to these depots
* Add group to the protect table, taking into account the existing permissions order.
* The script is idempotent.
* The depot must have a depth of 2.  
* There are two types of p4 directories, "dev" and "release".  A so a stream would look like this: *//MyProject/**dev**/Mainline*
* Must be able to take in a list of P4 users to add to the group.
* Logging for each step.



#### Nice to haves

* Add a README.md file to each stream.
* Adds missing users to the group if script is reran again but with new users.
* Add a creation time and description to each P4 item created.
* Pass in a list of other streams to add to the depot.
* Add a debug mode or dry-run mode.
* Validate p4 users.
* Create a docker image/container that runs this script.
* Ability to email or message the project owner.



### DO

* Keep it simple and easily maintainable by a human.



### Don'ts

* Don't use the existing new-p4-project-setup.sh script for reference!

