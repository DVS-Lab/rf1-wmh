# WMH and BAG, Ashley and Melanie
#MODIFIED from prelim HEART data by Tia and Cooper, 11-28-2023

######WD and Packages #######
# set wd for Melanie's mac
setwd('/Users/melaniekos/Library/CloudStorage/OneDrive-TempleUniversity/WMH + environmental stressors')

# set wd for Ashley's mac
# run this before you open code on your mac
setwd('~/Library/CloudStorage/OneDrive-TempleUniversity/WMH + environmental stressors')
getwd()

#Set Caroline's wd for PC 
setwd('~/WMH + environmental stressors')

#load packages for use 
# if a package is not installed, run the below in your Console:
# install.packages("") and insert package name in between the quotes 
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
####### Data transformation/cleaning #######
# load data 
wmh_data <- read.delim("truenet-summary-411.tsv")
rc_data <- read_csv("merged-data-wmh.csv")
bag_data <- read_csv("BAG_data_416.csv")
SES_rc_data <- read_csv("SES-merged-data.csv")
BrainAgeR <- read_csv("allsubs_brain_predicted.age.csv")
#Log transforming the WMH values 
wmh_log_df <- wmh_data %>%
  mutate(wmh_log = log(wmh))

#pull relevant info from SES-merged-data 

individual_ses <- subset(SES_rc_data, select = c(sub_id_x, ses_score_1, ses_score_2, ses_score_3, ses_score_4, ses_score_5, ses_score_6, ses_score_7, ses_4, sub_id_x, tppid, dob, age_mo, ethnicity_x, race_x, sub_gender, mspss_sum, zip_code))

colnames(individual_ses) <- c("subject","ses_score_1", "ses_score_2", "ses_score_3", "ses_score_4", "ses_score_5", "ses_score_6", "ses_score_7","ses_4","sub_2","tppid", "dob", "age_mo", "ethnicity", "race", "gender", "mspss_sum", "zip_code")
# Convert zip_code column to integer and then to character type
individual_ses$zip_code <- as.character(as.integer(individual_ses$zip_code))

SES_df <- subset(individual_ses, select = -sub_2)
# Convert zip_code column to character type
#individual_ses$zip_code <- as.character(individual_ses$zip_code)
#individual_ses$zip_code <- sprintf("%05s", individual_ses$zip_code)

#need to change the column name in rc_data to match wmh_log_df -->sub_id to subject

colnames(rc_data) <- c("wmh","subject","tppid","dob","age_mo","ethnicity","race","gender","mspss_sum","zip_code")

#remove original wmh values 
wmh_log_df <- subset(wmh_log_df, select = -wmh)

# created merged dataframe adding WMH value to df ...
 df <- merge(wmh_log_df, SES_df, by = "subject", all.x = TRUE)

 
 colnames(BrainAgeR) <- c("subject","age","brain.predicted_age","lower.Cl","upper.Cl","brainAge_gap","BAG")
 BrainAge_df <-merge(wmh_log_df, BrainAgeR, by = "subject")

 #adding BAG to the merged data 

df <- merge(df, bag_data, by = "subject", all.x = TRUE)

#removing the rounded ages column since it is redundent
df <- subset(df, select = -age)

#pulling only the needed variables 
#selected_data1 <- df[, colnames(df) %in% c("subject", "age_mo", "race", "gender", "wmh_log", "mspss_sum", "zip_code", "brainAge_gap")]

# separating h1 and h2 variables to maintain data and ensuring everyone is 18+ 


#load in files with stressors  
#Okay, I am not seeing the zip code for vacancy_data 
crime_data <- read.csv("crime_index_2023.csv")
residence_data <- read.csv("DP02_2021_5yr_residence1yearago.csv")
ses_data <- read.csv("ZIP_SES.csv")
renter_data <- read.csv("Renter-Owner Occupancy Status by ZIP.csv")

# Merge df and ses_data based on zip_code
merged_df <- merge(df, ses_data, by.x = 'zip_code', by.y = 'ZIP', all.x = TRUE)
# Create a new column ses_sum in df
#df$ses_sum <- ifelse(!is.na(merged_df$ses_sumranking), merged_df$ses_sumranking, NA)


# Merge merged_df and crime_data based on zip_code and ID
merged_df <- merge(merged_df, crime_data, by.x = 'zip_code', by.y = 'ID', all.x = TRUE)

# Create a new column crime in merged_df
merged_df$crime <- ifelse(!is.na(merged_df$CRMCYPERC), merged_df$CRMCYPERC, NA)

# Merge df and residence 1 year ago based on zip_code
merged_df <- merge(merged_df, residence_data, by.x = 'zip_code', by.y = 'ZIP', all.x = TRUE)

# merge df and vacancy 
# DP02_0081PE is the important information that we are looking at here! It is a percentage! 

# Merge df and owner/renter data
merged_df <- merge(merged_df, renter_data, by.x = 'zip_code', by.y = 'TL_GEO_ID', all.x = TRUE)
# List of row indices to be removed
rows_to_remove <- c(3, 13, 38, 39, 63, 89, 97,104)

# Remove rows by excluding the specified indices
merged_df <- merged_df[-rows_to_remove, ]

##### Analyses ########

#for SES_4 five and up 
#subset the data and look at regression of IV is gonna be ses then the same for the lower 

merged_df$high_ses <- merged_df$ses_4 >= 6
table(merged_df$high_ses)

higher_ses <- subset(merged_df, ses_4 >=6)
lower_ses <- subset(merged_df, ses_4 <=5)

merged_ses <- lm(ses_4 ~ BAG, data = merged_df)

summary(merged_ses)

# Remove rows with NA values from any column
cleaned_df <- merged_df %>%
  na.omit()

# Create bar plot
bar_plot <- ggplot(cleaned_df, aes(x = factor(high_ses), y = BAG, fill = factor(high_ses))) +
  geom_col(position = "dodge") +  # Use geom_col() for bar plot
  scale_fill_manual(values = c("darkblue", "lightblue"), labels = c("Low SES", "High SES")) +  # Set bar colors and legend labels
  labs(x = "Socioeconomic Status", y = "Brain-Age Gap", fill = "SES") +
  scale_x_discrete(labels = c("FALSE" = "Low SES", "TRUE" = "High SES")) +  # Set x-axis labels
  theme_minimal() +  # Apply a minimal theme
  theme(legend.title = element_text(size = 14),  # Set legend title text size
        legend.text = element_text(size = 17),  # Set legend text size
        axis.text.x = element_text(size = 17),  # Set x-axis label text size
        axis.text.y = element_text(size = 17),  # Set y-axis label text size
        axis.title.x = element_text(size = 20),  # Set x-axis title text size
        axis.title.y = element_text(size = 20))  # Set y-axis title text size

print(bar_plot)


ggplot(data = merged_df, aes(x = ses_4, y = BAG)) +
  geom_point()+
  geom_smooth(method = "lm", formula = "y~x", color = "blue") 

ggplot(data=merged_df, aes(x=, y=len)) +
  geom_bar(stat="identity", width=0.5)


######### MELANIE CODE ##########
reg_df <- subset(merged_df, select=c(subject, ses_4, wmh_log, BAG))
reg_df <- na.omit(reg_df)
reg_df

high_ses <- reg_df |> filter(ses_4 >= 6)
low_ses <- reg_df |> filter(ses_4 < 6)

a1 <- aov(BAG ~ as.factor(ses_4), data = reg_df)
summary(a1)
# marginal sig, 0.05, good to know

reg_df <- reg_df |> 
  mutate(ses_group=ifelse(ses_4 >= 6, "High SES", "Low SES"))

ses_mean <- aggregate(BAG ~ ses_group, data = reg_df, FUN = mean)
print(ses_mean)

# smaller dataset, lets wilcoxon rank
wilcox.test(BAG ~ ses_group, data=reg_df)
# no sig diff btwn two groups, ok

lm1 <- lm(BAG ~ ses_group, data=reg_df)
summary(lm1)

# graph
ggplot(reg_df, aes(x=as.factor(ses_4), y=BAG)) + 
  geom_violin() +
  xlab("Socioeconomic Status") +
  ylab("Brain Age Gap") + 
  ggtitle("Distribution of Brain Age Gap across Socioeconomic Status") +
  theme_minimal() +
  stat_compare_means(method = "t.test", label = "p.format") 




################################

high_ses_lm <- lm(higher_ses$ses_4 ~ higher_ses$BAG)

lower_ses_lm <- lm(ses_4 ~ BAG, data = lower_ses)
summary(high_ses_lm)

summary(aov(lower_ses$ses_4 ~ factor(lower_ses$wmh_log)))

boxplot(merged_df$ses_4 ~ factor(merged_df$wmh_log),
        xlab = "wmh_lob",ylab = "ses_4")

ggplot(data=merged_df, aes(x=wmh_log, y=ses_4)) +
  geom_point() +
  geom_smooth(data=higher_ses, method="lm", formula=y ~ x, color="lightblue") +
  geom_smooth(data=lower_ses, method="lm", formula=y ~ x, color="darkblue") +
  labs(title="Association between White Matter Hyperintensities and Socioeconomic Status",
       x="WMH Burden",
       y="Socioeconomic Status",
       caption="High SES determined as 6+ on MacArthur Scale of Subjective Social Status.")

#needs work
ggplot(data=merged_df, aes(x=BAG, y=ses_4)) +
  geom_point() +
  geom_smooth(data=higher_ses, aes(color="High SES"), method="lm", formula=y ~ x) +
  geom_smooth(data=lower_ses, aes(color="Low SES"), method="lm", formula=y ~ x) +
  labs(title="Association between Brain-Age Gap and Socioeconomic Status",
       x="Brain-Age Gap",
       y="Socioeconomic Status",
       caption="High SES determined as 6+ on MacArthur Scale of Subjective Social Status.",
       color="") +  # Clearing the default legend title
  scale_color_manual(values=c("lightblue", "darkblue"), labels=c("High SES", "Low SES")) +
  scale_x_continuous(breaks = seq(ceiling(min(merged_df$BAG)), floor(max(merged_df$BAG)), by = 1)) +
  scale_y_continuous(breaks = 1:10) +  # Specify breaks for ses_4 as 1 to 10
  theme(legend.position="bottom")



# Environmental stressors are crime (CRMCYPERC), residential instability (as moved_withinyr, raw number of residents
# reporting to moove within last year, AND renter occupied housing (renter_occ)), 
# and SES (SES_sum is 0 to 5, SES_ranking is 0 to 1)

# Social support is MSPSS score (1-7, var is mspss_sum)

## Let's start out easy and confirm that age has effect on wmh and bag ...

# wmh and age -- let's confirm 
wmh_age <- lm(wmh_log ~ age_mo, data = merged_df)
summary(wmh_age)
## There's significant correlation, p < 0.001 for effect of age on wmh 

#this is for just wmh before and after log transforming 
## MK EDIT - I SENT THIS GRAPH TO ASHLEY, THIS JUST CONFIRMS AGE EFFECT ON WMH 
# before log transform
ggplot(rc_data, aes(x = age_mo, y = wmh)) +
  geom_point() +  # points for each data point
  labs(title = "WMH",
       x = "Age (in years)",
       y = "White Matter Hyperintensity (wmh)")

# after log transform 
ggplot(merged_df, aes(x = age_mo, y = wmh_log)) +
  geom_point() +  # points for each data point
  geom_smooth(method = "lm", se = TRUE) +  # add regression line with shading for error
  labs(title = "White Matter Hyperintensity by Age",
       x = "Age (in years)",
       y = expression('WMH (Log scale, in mm'^3*')'), 
       caption = expression('Linear regression is significant, t(100) = 9.855, p < 0.001, ' * R^2 * ' = 0.4876.')) +
  theme(text = element_text(size = 17))  # Adjust the text size as needed

###### bag and age -- let's confirm
predicted_age <- lm(BAG ~ age_mo, data = merged_df)
summary(predicted_age)
# Significant correlation, p < 0.001 for effect of age on predicted age 
# Assuming 'merged_df' is your data frame with columns 'BAG' and 'wmh_log'
# Replace 'merged_df' with the actual name of your data frame if it's different

# Calculate correlation coefficient
na.omit(merged_df)

cor(BrainAge_df[c("BAG","wmh_log")],use = "complete.obs",method = "pearson")

correlation_coefficient <- cor(merged_df$BAG, merged_df$wmh_log)

print(paste("Correlation Coefficient between BAG and wmh_log:", correlation_coefficient))

help(cor)






# ok now plot in red -- this is BAG 
ggplot(merged_df, aes(x = age_mo, y = Pred_Age)) +
  geom_point() +  # points for each data point
  geom_smooth(method = "lm", se = TRUE, color = 'red') +  # add regression line with shading for error
  labs(title = "Brain-Age Gap (BAG)",
       x = "Age (in years)",
       y = expression('Predicted Age (in years)'), 
       caption = expression('Linear regression is significant, t(65) = 11.84, p < 0.001, ' * R^2 * ' = 0.68.')) +
  theme(text = element_text(size = 17))  # Adjust the text size as needed


# Create a sequence of values from 0 to 75 for x
x_seq <- seq(0, 75, length.out = 100)
y_seq <- seq(20, 75, by = 0.1)
# Calculate corresponding y values for the slope line


ggplot() +
  geom_point(data = merged_df, aes(x = age_mo, y = Pred_Age)) + # points for each data point
  geom_abline(intercept = 0, slope = 1, color = 'red') +  # add line with slope 1
  geom_ribbon(data = data.frame(x = x_seq, y = y_seq), aes(x = x, ymin = y, ymax = 75),
              fill = 'lightcoral', alpha = 0.5) +  # shading above the line
  labs(title = 'Brain-Age Gap',
       x = 'Age (in years)',
       y = expression('Predicted Age (in years)'),
       caption = expression('Slope = 1.')) +
  xlim(20, 75) +  # set x-axis limits
  ylim(20, 75) +  # set y-axis limits
  coord_fixed(ratio = 1) +  # enforce equal aspect ratio
  theme(text = element_text(size = 19))  # Adjust the text size as needed


# Assuming y_seq is generated based on some sequence or calculation
# Here's an example of generating y_seq from a sequence of numbers
y_seq <- seq(20, 75, by = 0.1)

# Assuming you have x_seq generated or you need to generate it similar to y_seq
x_seq <- seq(20, 75, by = 0.1)

# Now you can use x_seq and y_seq directly in geom_ribbon()
ggplot() +
  geom_point(data = merged_df, aes(x = age_mo, y = Pred_Age)) +
  geom_abline(intercept = 0, slope = 1, color = 'red') +
  geom_ribbon(data = data.frame(x = x_seq, y = y_seq), aes(x = x, ymin = y, ymax = 75),
              fill = 'lightcoral', alpha = 0.5) +
  labs(title = 'Brain-Age Gap',
       x = 'Age (in years)',
       y = 'Predicted Age (in years)',
       caption = 'Slope = 1.') +
  xlim(20, 75) +
  ylim(20, 75) +
  coord_fixed(ratio = 1) +
  theme(text = element_text(size = 19))

# age on BAG ... but because BAG already incorporates 'age' variable data, is it not autocorrelation?
bag_age <- lm(BAG ~ age_mo, data=merged_df)
summary(bag_age)
# Significant correlation, p < 0.001 for effect of age on BAG

# this is age effect on brain age gap... see above commentary
ggplot(merged_df, aes(x = age_mo, y = BAG)) +
  geom_point() +  # points for each data point
  geom_smooth(method = "lm", se = TRUE, color = 'red') +  # add regression line with shading for error
  labs(title = "Brain-Age Gap (BAG) by Age",
       x = "Age (in years)",
       y = expression('BAG (in years)'), 
       caption = expression('Linear regression is significant, t(65) = 22.7, p < 0.001, ' * R^2 * ' = 0.89.'))


# Oh, let's check gender effect on WMH or BAG
wmh_gender <- lm(wmh_log ~ gender, data = merged_df)
summary(wmh_gender)
# no significance 

bag_gender <- lm(brainAge_gap ~ gender, data=merged_df)
summary(bag_gender)
# no significance 


######## Let's check environmental stressors effect on wmh_log ########
## env stressors - crime, SES_sumranking, moved_withinyr, renter_occ

# need to aggregate data lol
# Define columns to exclude from aggregation
exclude_cols <- c("subject", "wmh_log","tppid","dob","age_mo",
                  "ethnicity","race","gender","mspss_sum", "brain.predicted_age",
                  "lower.CI","upper.CI","brainAge_gap","layer","NAME")

# Convert character columns to numeric
merged_df$total_residents <- as.numeric(merged_df$total_residents)
merged_df$same_withinyr <- as.numeric(merged_df$same_withinyr)
merged_df$perc_same_res <- as.numeric(merged_df$perc_same_res)
merged_df$moved_withinyr <- as.numeric(merged_df$moved_withinyr)
merged_df$perc_dif_res <- as.numeric(merged_df$perc_dif_res)

# Aggregate independent variables by zip code, excluding specified columns
aggregated_df <- aggregate(. ~ zip_code, data = merged_df[, !names(merged_df) %in% exclude_cols], FUN = mean, na.rm = TRUE)

# Retain wmh_log column
aggregated_df$wmh_log <- merged_df$wmh_log[match(aggregated_df$zip_code, merged_df$zip_code)]

# Perform regression analysis
h1_env_stress <- lm(wmh_log ~ crime + SES_sum + moved_withinyr + renter_occ, data = merged_df)

# View summary of regression results
summary(h1_env_stress)
# no significant results of environmental stressors on WMH ! 
plot(h1_env_stress) # residual check
vif(h1_env_stress) # multicollinearity check


# Ok let's factor in age and gender, as promised in pre-reg
h1_env_stressag <- lm(wmh_log ~ age_mo  + crime + SES_sum + moved_withinyr + renter_occ, data = merged_df)
summary(h1_env_stressag)
# significant effect only with age, classic
plot(h1_env_stressag) # residual check
vif(h1_env_stressag) # multicollinearity check


###### Ok, environmental stressors seemingly a bust, how about social support effect on WMH? ########
h2_soc_supp <- lm(wmh_log ~ mspss_sum, data = merged_df)
summary(h2_soc_supp)
# no significant results :(
plot(h2_soc_supp) # residual check
vif(h2_soc_supp) # multicollinearity check

# age and gender, as promised in pre-reg
h2_socsuppag <- lm(wmh_log ~ age_mo + gender + mspss_sum, data = merged_df)
summary(h2_socsuppag)
# haha, age significant again! 
plot(h2_socsuppag) # residual check
vif(h2_socsuppag) # multicollinearity check

#WMH and BAG effect?
wmh_bag_lm <- lm(wmh_log ~ BAG, data = merged_df)
summary(wmh_bag_lm)
#significance! 


# SES effect on WMH ?
wmh_SES <- lm(wmh_log ~ SES_sumranking, data = merged_df)
summary(wmh_SES)
# no significance... 

BAG_SES <- lm(BAG ~ SES_sumranking, data = merged_df)
summary(BAG_SES)

#Crime on BAG
BAG_Crime <- lm(BAG ~ crime, data = merged_df)
summary(BAG_Crime)
#no significance!

BAG_DA_stressors <- lm(BAG ~ crime + SES_sumranking + crime:SES_sumranking, data = merged_df)
summary(BAG_DA_stressors)

BAG_res_stress <- lm(BAG ~ renter_occ + moved_withinyr + renter_occ:moved_withinyr, data = merged_df)
summary(BAG_res_stress)

BAG_all_stressors <- lm(BAG ~ crime + SES_sumranking + renter_occ + moved_withinyr + crime:SES_sumranking:renter_occ:moved_withinyr, data = merged_df)
summary(BAG_all_stressors)

wmh_all_stress <- lm(wmh_log ~ crime + SES_sumranking + renter_occ + moved_withinyr + crime:SES_sumranking:renter_occ:moved_withinyr, data = merged_df)
summary(wmh_all_stress)

wmh_res_stress <- lm(wmh_log ~ renter_occ + moved_withinyr + renter_occ:moved_withinyr, data = merged_df)
summary(wmh_res_stress)

wmh_DA_stressors <- lm(wmh_log ~ crime + SES_sumranking + crime:SES_sumranking, data = merged_df)
summary(wmh_DA_stressors)

WMH_Crime <- lm(wmh_log ~ crime, data = merged_df)
summary(WMH_Crime)

#This plot is WMH and SES-- not going to plot any others if not sig / this is not sig so prob don't need on poster!
ggplot(merged_df, aes(x = SES_sumranking, y = wmh_log)) +
  geom_point() +
  labs(x = 'SES', y = 'WMH') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = TRUE) +
  labs(title = "White Matter Hyperintensities",
       x = "Socioeconomic Status",
       y = expression('WMH (Log scale, in mm'^3*')'), 
       caption = expression('Linear regression is not significant.'))

#relationship of BAG on WMH, Significant! 
ggplot(merged_df, aes(x = BAG, y = wmh_log)) +
  geom_point() +
  labs(x = 'BAG', y = 'WMH') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = TRUE, color = 'red') +
  labs(title = "WMH and Brain-Age Gap",
       x = "BAG",
       y = expression('WMH (Log scale, in mm'^3*')'), 
       caption = expression('Linear regression is significant, t(91) = -4.905, p < 0.001, '* R^2 *' = 0.2004.')) +
  theme(text = element_text(size = 17))  # Adjust the text size as needed


#SES and BAG
ggplot(merged_df, aes(x = SES_sumranking, y = BAG)) +
  geom_point() +
  labs(x = 'SES', y = 'BAG') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = TRUE, color = 'red') +
  labs(title = "Brain-Age Gap and Socioeconomic Status",
       x = "Socioeconomic Status",
       y = expression('Brain-Age Gap'), 
       caption = expression('Linear regression is not significant.')) +
  theme(text = element_text(size = 17))  # Adjust the text size as needed

#Crime and BAG
ggplot(merged_df, aes(x = crime, y = BAG)) +
  geom_point() +
  labs(x = 'Crime', y = 'BAG') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = TRUE, color = 'red') +
  labs(title = "Brain-Age Gap and Crime",
       x = "Crime",
       y = expression('Brain-Age Gap'), 
       caption = expression('Linear regression is significant, t(65) = -3.2, p = 0.002, '* R^2 * ' = 0.12 .')) +
  theme(text = element_text(size = 17))  # Adjust the text size as needed

ggplot(merged_df, aes(x = crime, y = wmh_log)) +
  geom_point() +
  labs(x = 'Crime', y = 'White Matter Hyperintensities') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = TRUE, color = 'blue') +
  labs(title = "White Matter Hyperintensities and Crime",
       x = "Crime",
       y = expression('White Matter Hyperintensities (Log scale, in mm'^3*')'), 
       caption = expression('Linear regression is not significant.')) +
  theme(text = element_text(size = 16.6))  # Adjust the text size as needed

# crime effect on WMH ?
m2 <- lm(wmh_log ~ crime, data = merged_df)
summary(m2)
# marginal significance at 0.089....

# residential instability effect on WMH? 


# gender effect on WMH?


# social support effect on WMH?
 


#This plot is WMH vs BAG
ggplot(merged_df, aes(x = BAG, y = wmh_log)) +
  geom_point() +
  labs(x = 'BAG', y = 'WMH (log)') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = FALSE) +
  aes(color = age_mo) +
  scale_color_continuous(name = '')

#This plot is age, wmh,crime
ggplot(merged_df, aes(x = age_mo, y = wmh_log)) +
  geom_point() +
  labs(x = 'Age (months)', y = 'WMH') +
  theme_minimal() +
  # regression line
  geom_smooth(method = 'lm', se = FALSE) +
  # ses as a color scale
  aes(color = crime) +
  scale_color_continuous(name = 'Crime')



#from Matt's code --> WMH, BAG and SES 


# Prepare the dataframe
merged_df_plot <- merged_df %>%
  mutate(
    SES_sumranking = if_else(
      SES_sumranking <=  0.5, as.factor("Lower"), as.factor("Higher"))
  )

axis_title <- 15
axis_text <- 15
legend_all <- 15

my_colors <- c("Lower" = "blue", "Higher" = "red")

# Create the plot
plot_wmh_bag_ses <- ggplot(merged_df_plot, aes(x = BAG, y = wmh_log, color = SES_sumranking, fill = SES_sumranking)) +
  geom_point(color = "grey") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_manual(values = my_colors, name = "SES") +  # Use manual scale for color
  scale_fill_manual(values = my_colors, name = "SES") +  # Use manual scale for fill
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "SES") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 20),  # Adjust the size of legend text
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20)
  ) +
  ylim(0.5, 10)

print(plot_wmh_bag_ses)

#

mean_ses <- mean(SES_sumranking)


#
merged_df_plot2 <- merged_df %>%
  mutate(
    crime = if_else(
      crime <= 167.2687, as.factor("Lower"), as.factor("Higher"))
  )
axis_title = 15
axis_text = 15
legend_all = 15
my_colors <- c("Low" = "blue", "High" = "red")
plot_wmh_bag_crime = ggplot(merged_df_plot2, aes(x = BAG, y = wmh_log , color = crime, fill = crime)) +
  geom_point(color = "gray")+
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "Crime") +
  scale_fill_discrete(name = "Crime") +
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "Crime") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20),
  ) +
  ylim(.5,10)
print(plot_wmh_bag_crime)







#WMH, BAG, and Crime
merged_df_plot2 <- merged_df %>%
  mutate(
    crime = if_else(
     crime <= 167.2687, as.factor("Lower"), as.factor("Higher"))
  )
axis_title = 15
axis_text = 15
legend_all = 15
my_colors <- c("Low" = "blue", "High" = "red")
plot_wmh_bag_crime = ggplot(merged_df_plot2, aes(x = BAG, y = wmh_log , color = crime, fill = crime)) +
  geom_point(color = "gray")+
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "Crime") +
  scale_fill_discrete(name = "Crime") +
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "Crime") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20),
  ) +
  ylim(.5,10)
print(plot_wmh_bag_crime)

merged_df_plot2 <- merged_df %>%
  mutate(
    crime = if_else(
      crime <= 167.2687, as.factor("Lower"), as.factor("Higher"))
  )

axis_title <- 15
axis_text <- 15
legend_all <- 15
my_colors <- c("Low" = "blue", "High" = "red")

# Create the plot
plot_wmh_bag_crime <- ggplot(merged_df_plot2, aes(x = BAG, y = wmh_log , color = crime, fill = crime)) +
  geom_point(color = "gray") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "Crime") +
  scale_fill_discrete(name = "Crime") +
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "Crime") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 20),  # Adjust the size of legend text
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20)
  ) +
  ylim(0.5, 10)

print(plot_wmh_bag_crime)

plot_wmh_bag_crime <- ggplot(merged_df_plot2, aes(x = BAG, y = wmh_log, color = crime)) +
  geom_point(color = "gray", aes(fill = crime)) +  # Set fill aesthetic inside aes() for points
  geom_smooth(aes(fill = crime), formula = y ~ x, method = "lm", se = TRUE) +  # Set fill aesthetic for lines
  scale_color_discrete(name = "Crime") +
  scale_fill_discrete(name = "Crime", guide = "none") +  # Hide the legend for fill
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "Crime") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 20),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20)
  ) +
  ylim(0.5, 10)

print(plot_wmh_bag_crime)


#WMH, BAG, and MSPSS 
na.omit(merged_df)
merged_df_plot3 <- merged_df %>%
  mutate(
    mspss_sum = if_else(
      mspss_sum <= 3.5, as.factor("Lower"), as.factor("Higher"))
  )
axis_title = 15
axis_text = 15
legend_all = 15
my_colors <- c("Low" = "blue", "High" = "red")
plot_wmh_bag_mspss = ggplot(merged_df_plot3, aes(x = BAG, y = wmh_log , color = mspss_sum, fill = mspss_sum)) +
  geom_point(color = "gray") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "MSPSS") +
  scale_fill_discrete(name = "MSPSS") +
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "MSPSS") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20),
  ) +
  ylim(.5,10)
print(plot_wmh_bag_mspss)
# List of row indices to remove
rows_to_remove <- c(5, 15, 20, 31, 36, 44, 48, 60, 73, 111)

# Remove specified rows
merged_df_plot3 <- merged_df_plot3[-rows_to_remove, ]

rows_to_remove <- c(5, 15, 20, 31, 36, 44, 48, 60, 73, 111)

# Filter out the rows
merged_df_plot3 <- merged_df %>%
  mutate(
    mspss_sum = if_else(
      mspss_sum <= 3.5, as.factor("Lower"), as.factor("Higher"))
  ) %>%
  filter(!row_number() %in% rows_to_remove)  # Remove specified rows

axis_title <- 15
axis_text <- 15
legend_all <- 15

my_colors <- c("Low" = "blue", "High" = "red")

plot_wmh_bag_mspss <- ggplot(merged_df_plot3, aes(x = BAG, y = wmh_log, color = mspss_sum, fill = mspss_sum)) +
  geom_point(color = "gray") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "MSPSS") +
  scale_fill_discrete(name = "MSPSS") +
  labs(x = "Brain-Age Gap", y = "White Matter Hyperintensities (log)", color = "MSPSS") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20)
  ) +
  ylim(0.5, 10)

print(plot_wmh_bag_mspss)




#WMH, SES, Crime, Age 
merged_df_plot4 <- merged_df %>%
  mutate(mspss_sum = if_else(
      mspss_sum <= 3.5, as.factor("Lower"), as.factor("Higher"))
  )
axis_title = 15
axis_text = 15
legend_all = 15
my_colors <- c("Low" = "blue", "High" = "red")
plot_wmh_ses_crime_age = ggplot(merged_df_plot4, aes(x = age_mo, y = wmh_log , color = mspss_sum, fill = mspss_sum)) +
  geom_point(color = "gray") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "MSPSS") +
  scale_fill_discrete(name = "MSPSS") +
  labs(x = "BAG", y = "WMH (log)", color = "MSPSS") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20),
  ) +
  ylim(.5,10)
print(plot_wmh_ses_crime_age)



# Filter out rows with NA mspss_sum
merged_df_plot4 <- merged_df %>%
  mutate(
    mspss_sum = if_else(
      mspss_sum <= 3.5, as.factor("Lower"), as.factor("Higher"))
  ) %>%
  filter(!is.na(mspss_sum))  # Remove rows with NA mspss_sum

axis_title <- 15
axis_text <- 15
legend_all <- 15

my_colors <- c("Low" = "blue", "High" = "red")

plot_wmh_ses_crime_age <- ggplot(merged_df_plot4, aes(x = age_mo, y = wmh_log, color = mspss_sum, fill = mspss_sum)) +
  geom_point(color = "gray") +
  geom_smooth(formula = y ~ x, method = "lm", se = TRUE) +
  scale_color_discrete(name = "MSPSS") +
  scale_fill_discrete(name = "MSPSS") +
  labs(x = "BAG", y = "WMH (log)", color = "MSPSS") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = 15),
    axis.title.x = element_text(size = 20),
    axis.title.y = element_text(size = 20),
  ) +
  ylim(0.5, 10)

print(plot_wmh_ses_crime_age)

### WMH SES crime age - Melanie 
merged_df_plot4 <- merged_df 
  
axis_title <- 15
axis_text <- 15
legend_all <- 15

plot_wmh_ses_crime_age <- ggplot(merged_df_plot4, aes(x = age_mo, y = wmh_log, color = SES_sumranking, fill = SES_sumranking)) +
  geom_point(aes(size = crime), shape = 21) +
  scale_color_gradient(name = "SES", low = "blue", high = "red") +
  scale_fill_gradient(name = "SES", low = "blue", high = "red") +
  scale_size_continuous(name = "Crime") +
  labs(x = "Age (months)", y = "WMH (log)", color = "SES") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = axis_text),
    axis.title.x = element_text(size = axis_title),
    axis.title.y = element_text(size = axis_title),
  ) +
  ylim(0, 10) +  #  ylim() adjust
  ggtitle("WMH, SES, Crime, and Age")

print(plot_wmh_ses_crime_age)

### BAG SES crime age - Melanie 
merged_df_plot5 <- merged_df 

axis_title <- 15
axis_text <- 15
legend_all <- 15

plot_bag_ses_crime_age <- ggplot(merged_df_plot5, aes(x = age_mo, y = brainAge_gap, color = SES_sumranking, fill = SES_sumranking)) +
  geom_point(aes(size = crime), shape = 21) +
  scale_color_gradient(name = "SES", low = "blue", high = "red") +
  scale_fill_gradient(name = "SES", low = "blue", high = "red") +
  scale_size_continuous(name = "Crime") +
  labs(x = "Age (months)", y = "BAG", color = "SES") +
  theme(
    legend.position = "right",
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    axis.text.x = element_text(size = axis_text),
    axis.text.y = element_text(size = axis_text),
    axis.title.x = element_text(size = axis_title),
    axis.title.y = element_text(size = axis_title),
  ) +
  # Adjust the range of y-axis to cover the full range of your data
  scale_y_continuous(limits = c(min(merged_df$brainAge_gap), max(merged_df$brainAge_gap))) +
  ggtitle("BAG, SES, Crime, and Age")

print(plot_bag_ses_crime_age)


