# Custom functions are camelCase. Arrays, parameters, and arguments are PascalCase
# Dependency functions are not embedded in master functions, and are marked with the flag dependency in the documentation
# []-notation is used wherever possible, and $-notation is avoided.

######################################### Load Required Libraries ###########################################
# Save and print the app start time
Start<-print(Sys.time())

# If running from UW-Madison
# Load or install the doParallel package
if (suppressWarnings(require("doParallel"))==FALSE) {
    install.packages("doParallel",repos="http://cran.cnr.berkeley.edu/");
    library("doParallel");
    }

# Load or install the RPostgreSQL package
if (suppressWarnings(require("RPostgreSQL"))==FALSE) {
    install.packages("RPostgreSQL",repos="http://cran.cnr.berkeley.edu/");
    library("RPostgreSQL");
    }

# Start a cluster for multicore, 3 by default or higher if passed as command line argument
CommandArgument<-commandArgs(TRUE)
if (length(CommandArgument)==0) {
     Cluster<-makeCluster(3)
     } else {
     Cluster<-makeCluster(as.numeric(CommandArgument[1]))
     }

#############################################################################################################
##################################### DATA DOWNLOAD FUNCTIONS, FIDELITY #####################################
#############################################################################################################
# No functions at this time

########################################### Data Download Script ############################################
# print current status to terminal 
print(paste("Load postgres tables",Sys.time()))

# If RUNNING FROM UW-MADISON:
# Download the config file
Credentials<-as.matrix(read.table("Credentials.yml",row.names=1))
# Connect to PostgreSQL
Driver <- dbDriver("PostgreSQL") # Establish database driver
Connection <- dbConnect(Driver, dbname = Credentials["database:",], host = Credentials["host:",], port = Credentials["port:",], user = Credentials["user:",])
# Query the sentences fro postgresql
DeepDiveData<-dbGetQuery(Connection,"SELECT docid, sentid, words, poses FROM nlp_sentences_352") 

# IF TESTING IN 402:
# Download data from Postgres:
#Driver <- dbDriver("PostgreSQL") # Establish database driver
#Connection <- dbConnect(Driver, dbname = "labuser", host = "localhost", port = 5432, user = "labuser")
#DeepDiveData<-dbGetQuery(Connection,"SELECT docid, sentid, words, poses FROM pbdb_fidelity.pbdb_fidelity_data")

# Record initial stats
Description1<-"Initial Data"
# Initial number of documents and rows in DeepDiveData
Docs1<-length((unique(DeepDiveData[,"docid"])))
Rows1<-nrow(DeepDiveData)
Clusters1<-0

#############################################################################################################
###################################### DATA CLEANING FUNCTIONS, FIDELITY ####################################
#############################################################################################################
# No functions at this time

############################################ Data Cleaning Script ###########################################
# print current status to terminal
print(paste("Clean DeepDiveData",Sys.time()))

# Remove bracket symbols ({ and }) from DeepDiveData sentences
DeepDiveData[,"words"]<-gsub("\\{|\\}","",DeepDiveData[,"words"])

# Replace "Fm" with "Formation" in words column
DeepDiveData[,"words"]<-gsub(",Fm,",",Formation,",DeepDiveData[,"words"])

# Remove bracket symbols ({ and }) from DeepDiveData poses column
DeepDiveData[,"poses"]<-gsub("\\{|\\}","",DeepDiveData[,"poses"])

# Remove commas from DeepDiveData poses column
DeepDiveData[,"poses"]<-gsub(","," ",DeepDiveData[,"poses"])

# Remove commas from DeepDiveData to prepare to run grep function
CleanedDDWords<-gsub(","," ",DeepDiveData[,"words"])

# Replace instances of "Fm" with "Formation"
CleanedDDWords<-gsub("Fm", "Formation", CleanedDDWords)

#############################################################################################################
###################################### FORMATION SEARCH FUNCTIONS, FIDELITY #################################
#############################################################################################################

########################################### Formation Search Script #########################################
# print current status 
print(paste("Search for the word ' formation' in DeepDiveData sentences",Sys.time()))

# Apply grep to the object cleaned words
FormationHits<-grep(" formation", ignore.case=TRUE, perl = TRUE, CleanedDDWords)
# Extact DeepDiveData rows corresponding with formation hits
SubsetDeepDive<-DeepDiveData[FormationHits,]

# Update the stats table
Description2<-"Subset DeepDiveData to rows which contain the word 'formation'"
# Record number of documents and rows in SubsetDeepDive:
Docs2<-length((unique(SubsetDeepDive[,"docid"])))
Rows2<-nrow(SubsetDeepDive)
Clusters2<-0
    
# Remove SubsetDeepDive sentences that are more than 350 characters in length
ShortSent<-sapply(SubsetDeepDive[,"words"], function(x) as.character(nchar(x)<=350))
# Remove sentences that exceed the character limit from SubsetDeepDive
SubsetDeepDive<-SubsetDeepDive[which(ShortSent==TRUE),]
    
# Update the stats table
Description3<-"Remove sentences exceeding 350 characters"
# Record number of documents and rows in SubsetDeepDive:
Docs3<-length((unique(SubsetDeepDive[,"docid"])))
Rows3<-nrow(SubsetDeepDive)
Clusters3<-0

#############################################################################################################
####################################### NNP CLUSTER FUNCTIONS, FIDELITY #####################################
#############################################################################################################
# Consecutive word position locater function:
findConsecutive<-function(DeepDivePoses) {
    Breaks<-c(0,which(diff(DeepDivePoses)!=1),length(DeepDivePoses))
    ConsecutiveList<-lapply(seq(length(Breaks)-1),function(x) DeepDivePoses[(Breaks[x]+1):Breaks[x+1]])
    return(ConsecutiveList)
    }

############################################## NNP Cluster Script ###########################################
# Replace slashes from SubsetDeepDive words and poses columns with the word "SLASH"
SubsetDeepDive[,"words"]<-gsub("\"","SLASH",SubsetDeepDive[,"words"])
SubsetDeepDive[,"poses"]<-gsub("\"","SLASH",SubsetDeepDive[,"poses"])

# print current status to terminal
print(paste("Extract NNPs from SubsetDeepDive rows",Sys.time()))

# Create a list of vectors showing each formation hit sentence's unlisted poses column 
DeepDivePoses<-parSapply(Cluster, SubsetDeepDive[,"poses"],function(x) unlist(strsplit(as.character(x)," ")))
# Assign names to each list element corresponding to the row in SubsetDeepDive
names(DeepDivePoses)<-1:nrow(SubsetDeepDive)

# Extract all the NNPs from DeepDivePoses
# NOTE: Search for CC as to get hits like "Middendorf And Black Creek Formations" which is NNP, CC, NNP, NNP, NNP
DeepDiveNNPs<-parSapply(Cluster, DeepDivePoses,function(x) which(x=="NNP"|x=="CC"))
    
# print current status to terminal
print(paste("Find consecutive NNPs in DeepDiveNNPs",Sys.time()))
    
# Apply function to DeepDiveNNPs list
ConsecutiveNNPs<-sapply(DeepDiveNNPs, findConsecutive)   
# Collapse each cluster into a single character string such that each sentence from formation hits shows its associated clusters    
SentenceNNPs<-sapply(ConsecutiveNNPs,function(y) sapply(y,function(x) paste(x,collapse=",")))
    
# print current status to terminal
print(paste("Find words Associated with Conescutive NNPs",Sys.time()))
    
# Create a data frame with a row for each NNP cluster
# Make a column for cluster elements 
ClusterPosition<-unlist(SentenceNNPs)
# Make a column for sentence IDs
ClusterCount<-sapply(SentenceNNPs,length)
# Repeat the SubsetDeepDive row number (denoted in the names of SentenceNNPs) by the number of NNP clusters in each sentence
SubsetDDRow<-rep(names(SentenceNNPs),times=ClusterCount)
# Bind cluster position data with the row number data
ClusterData<-as.data.frame(cbind(ClusterPosition,SubsetDDRow))
# Reformat the data
ClusterData[,"SubsetDDRow"]<-as.numeric(as.character(ClusterData[,"SubsetDDRow"]))
# Remove NA's from ClusterData
ClusterData<-ClusterData[which(ClusterData[,"ClusterPosition"]!="NA"),]
# Create columns for docid and sentid data for each cluster
docid<-SubsetDeepDive[ClusterData[,"SubsetDDRow"],"docid"]
sentid<-SubsetDeepDive[ClusterData[,"SubsetDDRow"],"sentid"]
# Bind the data to the data frame
ClusterData<-cbind(ClusterData, docid, sentid)
    
# Reformat ClusterData
ClusterData[,"ClusterPosition"]<-as.character(ClusterData[,"ClusterPosition"])
ClusterData[,"docid"]<-as.character(ClusterData[,"docid"])
ClusterData[,"sentid"]<-as.numeric(as.character(ClusterData[,"sentid"]))
ClusterData[,"SubsetDDRow"]<-as.numeric(as.character(ClusterData[,"SubsetDDRow"]))
 
# Extract the sentences for the associated SubsetDeepDive rows  
ClusterSentences<-sapply(ClusterData[,"SubsetDDRow"], function (x) SubsetDeepDive[x,"words"])
# Split and unlist the words in each cluster sentence
ClusterSentencesSplit<-sapply(ClusterSentences,function(x) unlist(strsplit(as.character(x),",")))
# Extract the NNP Clusters from theh associate sentences 
# Get numeric elements for each NNP Cluster word
NNPElements<-lapply(ClusterData[,"ClusterPosition"],function(x) as.numeric(unlist(strsplit(x,","))))
# Create a vector for the number of Clusters in ClusterData
NumClusterVector<-1:nrow(ClusterData) 
# Extract the words from ClusterSentencesSplit       
ClusterWords<-sapply(NumClusterVector, function(y) sapply(NNPElements[y], function(x) ClusterSentencesSplit[[y]][x]))
# Collapse the clusters into single character strings
NNPWords<-sapply(ClusterWords, function(x) paste(array(x), collapse=" "))
# Bind the clusters to the ClusterData frame
ClusterData[,"NNPWords"]<-NNPWords
    
# Update the stats table
Description4<-"Extract NPP clusters from SubsetDeepDive rows"
# Record number of documents and rows in SubsetDeepDive:
Docs4<-length(unique(ClusterData[,"docid"]))
Rows4<-length(unique(ClusterData[,"SubsetDDRow"]))
Clusters4<-nrow(ClusterData)

#############################################################################################################
##################################### FORMATION CLUSTERS FUNCTIONS, FIDELITY ################################
#############################################################################################################    
# Capitalization function from stack exchane
simpleCap <- function(x) {
  s <- strsplit(x, " ")[[1]]
  paste(toupper(substring(s, 1,1)), substring(s, 2),
      sep="", collapse=" ")
}
    
########################################### Formation Clusters Script #######################################
# print current status to terminal
print(paste("Extract 'formation' clusters from ClusterData",Sys.time()))
    
# Find NNP clusters with the world formation in them
FormationClusters<-grep(" formation",ClusterData[,"NNPWords"],ignore.case=TRUE,perl=TRUE) # We could do a search for tail, to ensure it's the last word
# Extract those rows from ClusterData
FormationData<-ClusterData[FormationClusters,]
FormationData[,"docid"]<-as.character(FormationData[,"docid"])
    
# Find non-formation clusters
PostFmClusters<-ClusterData[-FormationClusters,]
    
# Update the stats table
Description5<-"Extract NNP clusters containing the word 'formation'"
# Record number of documents and rows in SubsetDeepDive:
Docs5<-length(unique(FormationData[,"docid"]))
Rows5<-length(unique(FormationData[,"SubsetDDRow"]))
Clusters5<-nrow(FormationData)  
    
# print current status to terminal
print(paste("Capitalize formation names appropriately",Sys.time()))
    
# Make all characters in the NNPWords column lower case
FormationData[,"NNPWords"]<-tolower(FormationData[,"NNPWords"])
# Apply simpleCap function to NNPWords column so the first letter of every word is capitalized.
FormationData[,"NNPWords"]<-sapply(FormationData[,"NNPWords"], simpleCap)
    
# print current status to terminal
print(paste(" Remove all characters after 'Formation' or 'Formations'",Sys.time()))
    
# Account for romance language exceptions
Des<-grep("Des",FormationData[,"NNPWords"], perl=TRUE, ignore.case=TRUE)
Les<-grep("Les",FormationData[,"NNPWords"], perl=TRUE, ignore.case=TRUE)
FrenchRows<-c(Des,Les)
    
# Extract FormationData NNPWords with "Formations" NNP clusters
PluralWithFrench<-grep("Formations",FormationData[,"NNPWords"], perl=TRUE, ignore.case=TRUE)
# Make sure character removal is not performed on french rows
Plural<-PluralWithFrench[which(!PluralWithFrench%in%FrenchRows)]
# Replace (non-french) plural rows of NNPWords column with version with characters after "formations" removed
FormationsCut<-gsub("(Formations).*","\\1",FormationData[Plural,"NNPWords"])
FormationData[Plural,"NNPWords"]<-FormationsCut
    
# Extract FormationData NNPWords with "Formation" NNP clusters
# Find the FormationData NNPWords rows with "Formation" NNP clusters (NON PLURALS)
SingularWithFrench<-which(!1:nrow(FormationData)%in%Plural)
# Make sure character removal is not performed on french rows
Singular<-SingularWithFrench[which(!SingularWithFrench%in%FrenchRows)]
# Replace (non-french) singular rows of NNPWords column with version with characters after "formation" removed
FormationCut<-gsub("(Formation).*","\\1",FormationData[Singular,"NNPWords"])
FormationData[Singular,"NNPWords"]<-FormationCut
    
# Remove FormationData rows which only have "Formation" in the NNPWords column
FormationData<-FormationData[-which(FormationData[,"NNPWords"]=="Formation"),]
 
# Update the stats table
Description6<-"Remove rows that are just the word 'Formation'"
# Record number of documents and rows in SubsetDeepDive:
Docs6<-length(unique(FormationData[,"docid"]))
Rows6<-length(unique(FormationData[,"SubsetDDRow"]))
Clusters6<-nrow(FormationData)        
       
# STEP THIRTEEN: Split the NNPClusters where there is an "And"
SplitFormations<-strsplit(FormationData[,"NNPWords"],'And ')
# Remove the blanks created by the splitting
SplitFormationsClean<-sapply(SplitFormations,function(x) unlist(x)[unlist(x)!=""])   
# SplitFormations is a list of the split clusters. Figure out which clusters were split at "And" using length.
SplitCount<-sapply(SplitFormationsClean,length)
# Repeat the data in FormationData for each split cluster by its length
SubsetDDRow<-rep(FormationData[,"SubsetDDRow"],time=SplitCount)
ClusterPosition<-rep(FormationData[,"ClusterPosition"],times=SplitCount) 
docid<-rep(FormationData[,"docid"],times=SplitCount) 
sentid<-rep(FormationData[,"sentid"],times=SplitCount)
# Make a column for the split formations
Formation<-unlist(SplitFormationsClean)
FormationData<-as.data.frame(cbind(Formation,SubsetDDRow,ClusterPosition,docid,sentid))
# Reformat data
FormationData[,"SubsetDDRow"]<-as.numeric(as.character(FormationData[,"SubsetDDRow"]))
FormationData[,"Formation"]<-as.character(FormationData[,"Formation"])
FormationData[,"ClusterPosition"]<-as.character(FormationData[,"ClusterPosition"])
FormationData[,"docid"]<-as.character(FormationData[,"docid"])
FormationData[,"sentid"]<-as.numeric(as.character(FormationData[,"sentid"]))

# Paste "Formation" to the end of the split clusters where it is missing
# Determine the split clusters that DO contain the word "Formation"
FormationHalves<-grep("Formation",FormationData[,"Formation"], perl=TRUE, ignore.case=TRUE)
# Paste "Formation" to all of the non FormationHalves rows
FormationData[-FormationHalves,"Formation"]<-paste(FormationData[-FormationHalves,"Formation"], "Formation", sep=" ")
    
# Update the stats table
Description7<-"Split NNPClusters at 'And'"
# Record number of documents and rows in SubsetDeepDive:
Docs7<-length(unique(FormationData[,"docid"]))
Rows7<-length(unique(FormationData[,"SubsetDDRow"]))
Clusters7<-nrow(FormationData)
  
# STEP FOURTEEN: Remove Formations that equal to 1 word in length or more than 5 words in length.
print(paste("Remove Formations > 5 or = 1 word(s) in length",Sys.time()))
# Determine the number of words in each NNPWords row
WordLength<-sapply(sapply(FormationData[,"ClusterPosition"], function(x) strsplit(x, ",")), function(x) length(x))
# Determine which rows have more than 5 NNPWords or only 1 NNPWord
BadFormations<-which(WordLength>5|WordLength==1)
# Remove those rows from FormationData
FormationData<-FormationData[-BadFormations,]

# Update the stats table
Description8<-"Remove Formations > 5 words in length"
# Record number of documents and rows in SubsetDeepDive:
Docs8<-length(unique(FormationData[,"docid"]))
Rows8<-dim(unique(FormationData[,c("docid","sentid")]))[1]
Clusters8<-nrow(FormationData) 

# STEP FIFTEEN: Clean FormationData
print(paste("Clean FormationData",Sys.time()))
# Remove spaces at the beginning and/or end of the Formation column where necessary
FormationData[,"Formation"]<-trimws(FormationData[,"Formation"], which=c("both"))
# Remove double spaces in the formation column
FormationData[,"Formation"]<-gsub("  "," ",FormationData[,"Formation"])
# Remove s in "Formations" where necessary
FormationData[,"Formation"]<-gsub("Formations","Formation",FormationData[,"Formation"])
    
# STEP SIXTEEN: Write outputs
print(paste("Writing Outputs",Sys.time()))
     
# Extract columns of interest for the output
FormationData<-FormationData[,c("Formation","docid","sentid")]
   
# Return formation stats table  
StepDescription<-c(Description1, Description2, Description3, Description4, Description5, Description6, Description7, Description8)
NumberDocuments<-c(Docs1, Docs2, Docs3, Docs4, Docs5, Docs6, Docs7, Docs8)
NumberRows<-c(Rows1, Rows2, Rows3, Rows4, Rows5, Rows6, Rows7,Rows8)
NumberClusters<-c(Clusters1, Clusters2, Clusters3, Clusters4, Clusters5, Clusters6, Clusters7, Clusters8) 
# Bind formation stats columns
Stats<-cbind(StepDescription,NumberDocuments,NumberRows,NumberClusters)  

# Set directory for output
CurrentDirectory<-getwd()
setwd(paste(CurrentDirectory,"/output",sep=""))
    
# Clear any old output files
unlink("*")

# Write csv output files
write.csv(PostFmClusters, "PostFmClusters.csv")
write.csv(FormationData, "FormationData.csv")
write.csv(Stats, "Stats.csv")
    
# Stop the cluster
stopCluster(Cluster)

# COMPLETE
print(paste("Complete",Sys.time())) 
