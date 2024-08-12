#Correlation Matrix 

######Set WD and ########
#Ashley's working directory
setwd('~/Library/CloudStorage/OneDrive-TempleUniversity/WMH + environmental stressors')

#Load in packages 
library(car)
library(plyr)
library(foreign)
library(pscl)
library(boot)
library(MASS)
library(robust)
library(sfsmisc)
library(ggplot2)
library(reshape2)
library(ppcor)
library(ggrepel)
library(Hmisc)
library(tidyverse)
library(sandwich)
library(ggpubr)
library(interactions)
library(knitr)
library(twowaytests)
library(ggfortify)
library(interactions)
library(broom)
library(patchwork)
library(robustbase)
library(lmtest)
library(modelr)
library(Rmisc)
library(ggplot2)
library(dplyr)
library(Hmisc)
library(corrplot)
########### Load in data and making the matrix######
df <- read_csv("noddi-summary.csv")

# Select only the numeric columns from the dataframe
numeric_data <- df %>% select(where(is.numeric))

# Compute the correlation matrix
cor_matrix <- cor(numeric_data, use = "complete.obs")

# Print the correlation matrix
print(cor_matrix)

# Select only the numeric columns from the dataframe
numeric_data <- df %>% select(where(is.numeric))

# Compute the correlation matrix
cor_matrix <- cor(numeric_data, use = "complete.obs")

# Visualize the correlation matrix using corrplot
corrplot(cor_matrix, method = "color")
