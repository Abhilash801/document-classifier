#install and load required packages
if(!require(tm))
install.packages("tm")
if(!require(class))
install.packages("class")
if(!require(SnowballC))
install.packages("SnowballC")
if(!require(stringr))
install.packages("stringr")
if(!require(RCurl))
install.packages("RCurl")
if(!require(XML))
install.packages("XML")
if(!require(nnet))
install.packages("nnet")
if(!require(plyr))
install.packages("plyr")
library(nnet)
library(rpart)
library(tm)
library(class)
library(SnowballC)
library(stringr)
library(RCurl)
library(XML)
library(base)
library(plyr)

#======================setting file paths===========================================
#setting root directory and other sub folder paths
rootDirectory="C:/Desktop/small training"

# sub folders under root directory, your root folder should contain following folders
positive.foldername=paste(rootDirectory,"positive",sep = "/")
negative.foldername=paste(rootDirectory,"negative",sep = "/")
testFiles.foldername=paste(rootDirectory,"testfiles",sep="/")

#following two folders are created by the script to store plain texts of the input html files
positiveTextfiles.foldername=paste(rootDirectory,"positivetexts",sep = "/")
negativeTextFiles.foldername=paste(rootDirectory,"negativetexts",sep = "/")
testTextFiles.foldername=paste(rootDirectory,"testfilestexts",sep = "/")

#setting the root directory
setwd(rootDirectory)


#============= preparing files for building a document corpus==============================

#get file names from positive training folder and remove any  text,powershell files
removeFileNames=list.files(positive.foldername,pattern = "\\.(txt|ps1)$")
fileNames.positive=list.files(positive.foldername)                   
fileNames.positive=fileNames.positive[!(fileNames.positive %in% removeFileNames)]

#fet filenames from negative training folder as well
removeFileNames.negative=list.files(negative.foldername,pattern = "\\.(txt|ps1)$")
fileNames.negative=list.files(negative.foldername)                   
fileNames.negative=fileNames.negative[!(fileNames.negative %in% removeFileNames.negative)]


#deleting any files from previous run from the text files path
if(dir.exists(positiveTextfiles.foldername))
  unlink(positiveTextfiles.foldername)

#create folder for holding text files if it is not created
dir.create(positiveTextfiles.foldername,showWarnings=FALSE)

#similarly for negative files
if(dir.exists(negativeTextFiles.foldername))
  unlink(negativeTextFiles.foldername)

dir.create(negativeTextFiles.foldername,showWarnings=FALSE)

#function to convert html file to plain text
HtmlToText=function (fileName,subPath)#** fileName= name of the file, subPath= sub folder name under root dir
{
  fullFilePath=paste(rootDirectory,subPath,fileName,sep = "/")
  rawHTML=paste(readLines(fullFilePath),collapse="\n")
  html <- htmlTreeParse(rawHTML, useInternal = TRUE)
  txt <- xpathApply(html, "//body//text()[not(ancestor::script)][not(ancestor::style)][not(ancestor::noscript)]", xmlValue)
  setwd(paste(rootDirectory,'/',subPath,'Texts',sep = ''))
  #create and write text content to the files
  if(!file.exists(paste(fileName,'txt',sep = ".")))
  file.create(paste(fileName,'txt',sep = "."))
  fileConn<-file(paste(fileName,'txt',sep = "."))
  writeLines(unlist(txt),fileConn)
  close(fileConn)
  setwd(rootDirectory)
}

#parse html pages and extract plain text to seperate files
lapply(fileNames.positive,subPath='positive',HtmlToText)
lapply(fileNames.negative,subPath='negative',HtmlToText)

#================= creating and preprocessing of corpus of documents================
#creating corpus for positive documents
disease.TrainPositive = Corpus(DirSource(positiveTextfiles.foldername))
summary(disease.TrainPositive)

#creating corpus for negative documents
disease.TrainNegative= Corpus(DirSource(negativeTextFiles.foldername))
summary(disease.TrainNegative)

# Merging both types of corpuses for preprocessing
disease.Corpus= c(disease.TrainPositive,disease.TrainNegative)
disease.Corpus

#preprocessing the corpus
disease.Corpus=tm_map(disease.Corpus,content_transformer(tolower))#atomic vector error to access metadata
disease.Corpus=tm_map(disease.Corpus,removePunctuation)
disease.Corpus=tm_map(disease.Corpus,removeNumbers)
disease.Corpus=tm_map(disease.Corpus,removeWords,stopwords(kind = 'smart'))
disease.Corpus=tm_map(disease.Corpus,content_transformer(stemDocument))
disease.Corpus=tm_map(disease.Corpus,stripWhitespace)
disease.Corpus=tm_map(disease.Corpus,content_transformer(PlainTextDocument))



#creating document term matrix with inverse document frequency
disease.tdm=TermDocumentMatrix(disease.Corpus)
dim(disease.tdm)
disease.dtm=DocumentTermMatrix(disease.Corpus,control=list(weighing=weightTfIdf(disease.tdm),
                                                           minWordLength=2))
disease.dtm.cleaned=disease.dtm #creating a copy of corpus for further processing


#================== cleaning corpus by removing terms and converting it to data frame to train models=======

# reference http://stackoverflow.com/questions/25905144/
#***x is the corpus of documents , pct- terms which are in more than pct% of documents are removed from corpus
removeCommonTerms = function (x, pct) 
{
  stopifnot(inherits(x, c("DocumentTermMatrix", "TermDocumentMatrix")), 
            is.numeric(pct), pct > 0, pct < 1)
  m = if (inherits(x, "DocumentTermMatrix")) 
    t(x)
  else x
  t = table(m$i) < m$ncol * (pct)
  termIndex = as.numeric(names(t[t]))
  if (inherits(x, "DocumentTermMatrix")) 
    x[, termIndex]
  else x[termIndex, ]
}

#removing words which are present in morethan 60% of documents and less than 10 % of documents,
# other wise we need to deal with >500000 terms which is undesirable.
disease.dtm.cleaned=removeCommonTerms(disease.dtm.cleaned ,.6)
disease.dtm.cleaned=removeSparseTerms(disease.dtm.cleaned,.90)
dim(disease.dtm.cleaned)


#converting dtm to data frame to run the training algorithms
disease.df=as.data.frame(inspect(disease.dtm.cleaned))
dim(disease.df)

#manually removing features which are evidenlty irrelevant, this step is cumbersome
# and usually involves lot of iterations to filter.Limiting it to basic filtering for the scope of project.
disease.df=disease.df[, !colnames(disease.df) %in% c("ufeff","uuuuuauu","uuuuucc","uuauuuuduucuau"
                                                       ,"ueucua","español","iii","icd")]

colnames(disease.df)

#marking the class in data frame, marking based on the number of positive and negative documents 
doc.class=c(rep("positive",length(disease.TrainPositive)),rep("negative",length(disease.TrainNegative)))
disease.df=cbind(disease.df,doc.class)


#=====================prediction with neural network================================

#dividing data to train and test 70% train and 30% test

index=sample(1:nrow(disease.df), size=0.7*nrow(disease.df))
disease.df.train=disease.df[index, ]
disease.df.test= disease.df[-index,]
nnet.classifier = nnet(doc.class ~., data=disease.df.train,size=2, rang=0.01,decay=5e-4, maxit=200)
#** keeping decay very less to avoid overfitting used one of the recommended values, rang=.01 this sets majority
#** of the inputs close to 1. using 2 layers and 200 iterations 

predictions = predict(nnet.classifier, disease.df.test, type='class')
summary(disease.df.train)

#evaluating results with confusion matrix
confusion.matrix=table(disease.df.test$doc.class,predict(nnet.classifier, disease.df.test, type='class'))
true.negative=confusion.matrix[1,1]
false.positive=confusion.matrix[1,2]
false.negative=confusion.matrix[2,1]
true.positive=confusion.matrix[2,2]

#computing and writing precision,recall and accuracy to text file
nnet.precision= as.character(round(true.positive/(true.positive+false.positive),3))
nnet.recall= as.character(round(true.positive/(true.positive+false.negative),3))
nnet.accuracy= as.character(round((true.positive+true.negative)/(true.positive+true.negative+false.negative+false.positive),3))
write.table(confusion.matrix,"modelresults.txt")
fileConn<-file("modelresults.txt")

writeLines(c("=========neural net - evaluation metrics==============",
             paste("precision = ",nnet.precision),paste("recall =  ",nnet.recall),
paste("accuracy = ",nnet.accuracy)), fileConn)
close(fileConn)                          


#**************prediction with regression tree **********************************
#dividing data into train and test sets

knn.index=sample(1:nrow(disease.df),size=0.7*nrow(disease.df))
knndisease.df.train=disease.df[knn.index,]
knndisease.df.test=disease.df[-knn.index,]

#predicting doc.class from the terms available in dtm
knntree=rpart(doc.class~.,data = knndisease.df.train)
knntree.predictions=predict(knntree,knndisease.df.test,type='class')

#evaluation of results with confusion matrix
table(knntree.predictions,knndisease.df.test$doc.class)

confusion.matrix=table(disease.df.test$doc.class,predict(knntree, disease.df.test, type='class'))
true.negative=confusion.matrix[1,1]
false.positive=confusion.matrix[1,2]
false.negative=confusion.matrix[2,1]
true.positive=confusion.matrix[2,2]

#computing and writing precision,recall and accuracy to text file
knn.precision= as.character(round(true.positive/(true.positive+false.positive),3))
knn.recall= as.character(round(true.positive/(true.positive+false.negative),3))
knn.accuracy= as.character(round((true.positive+true.negative)/(true.positive+true.negative+false.negative+false.positive),3))
write.table(confusion.matrix,"modelresults.txt")
fileConn<-file("modelresults.txt")

writeLines(c("=========rpart - evaluation metrics==============",
             paste("precision = ",rpart.precision),paste("recall =  ",rpart.recall),
paste("accuracy = ",rpart.accuracy)), fileConn)
close(fileConn)             




#========auto summarizing predicted disease articles along with their description to a csv file=====================

predicted.disease.files=row.names(disease.df.test[predictions=='positive',])

summarize.disease=function(fileloc) #** pass the file name to extract summary for
{
  
  fileloc=substr(fileloc,1,nchar(fileloc)-4)
  #not summarizing files which are falsely predicted to be disease files
  fileName = paste(rootDirectory,'positive',fileloc,sep = '/')
  disease.results=data.frame()
  if(file.exists(fileName)) 
  {
    rawHTML=paste(readLines(fileName),collapse="\n")
    html= htmlTreeParse(rawHTML, useInternal = TRUE)
    title=xpathSApply(html,"//title",xmlValue)
    #trimming for disease name
    title=gsub("- Wikipedia, the free encyclopedia", "", title)
    #extracting disease summary which is the first <p> tag in a wiki article
    text.list=xpathApply(html, '//p', xmlValue)
  
    disease.results=data.frame(disease.filename=fileloc,disease.name=title,
                               disease.summary=as.character(text.list[1]))
    
  }
  
  #remove duplicates and write data to csv
  if(file.exists('diseaseresults.csv'))
  {
    oldfile=read.csv(file='diseaseresults.csv',header = TRUE)
    alldata=rbind(oldfile[2:4],disease.results)
  } else{
    alldata=disease.results}
  
  write.csv(alldata,file='diseaseresults.csv')
}


#call for summarizing disease files
lapply(predicted.disease.files, summarize.disease)



