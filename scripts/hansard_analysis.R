# load ----
pacman::p_load(tidyverse, stringr, forcats, purrr, magrittr, tidytext, reshape2, wordcloud)
full_speeches <- readRDS("data//full_speeches.RDAT")
appearances_tib <- readRDS("data//appearances.RDAT")

tidy_dtm <- appearances_tib %>% 
  mutate(r = row_number()) %>% 
  unnest_tokens(word, speeches) %>% 
  group_by(name, r, word) %>% 
  summarise(count = length(word)) %>%
  arrange(r)

eu <- read_file("data/European Union (Notification of Withdrawal) Bill 2017-03-01 (1).txt")
source('scripts\\main_src.R')

# extract ----

names <- extract_names(eu)
appearances_tib <- get_parties(names)

# Manually fix Lords missing parties ----
appearances_tib %>% filter(is.na(party)) %>% unique()

# The Archbishop and Baroness are not assigned a party. 
str_subset(names, "Headley|Elie|York|Scone") %>% unique()

for (i in seq_along(appearances_tib$name)) {
  if (appearances_tib$name[i] == "Lord Bridges of Headley"){
    appearances_tib$party[i] = "(Con)"
  } else if (appearances_tib$name[i] == "Lord Keen of Elie") {
    appearances_tib$party[i] = "(Con)"
  } else if (str_detect(appearances_tib$name[i], "Advocate-General")) {
    appearances_tib$name[i] = "Lord Bridges of Headley"
  } else if (str_detect(appearances_tib$name[i], "Parliamentary Under-Secretary")) {
    appearances_tib$name[i] = "Lord Keen of Elie"
  }
}

# Add more variables ----

appearances_tib %<>% add_gender()

appearances_tib %<>% bind_speeches()

speech_tib <- reduce_speeches(appearances_tib)

saveRDS(appearances_tib, "data//appearances.RDAT")
saveRDS(speech_tib, "data//full_speeches.RDAT")

# The basics: ----

# team composition ----

speech_tib %>% group_by(party, gender) %>% summarise(n = n()) %>%
  ggplot(aes(party, n)) +
  geom_col(aes(fill = gender)) +
  ylab("# members") +
  scale_y_continuous(breaks = seq(0,30,5))

full_speeches

appearances_tib <- readRDS("data//appearances.RDAT")

# word counts by gender ----

words_per_speech <- appearances_tib %>% mutate(r = row_number()) %>% unnest_tokens(word, speeches) %>% 
  group_by(r, name) %>% summarise(word_count = n())
words_per_speech

words_per_lord <- words_per_speech %>% group_by(name) %>% summarise(word_count = sum(word_count)) %>% filter(!is.na(name))
words_per_lord 

words_per_speech %>% left_join(distinct(appearances_tib, name, party)) %>% ggplot(aes(r, word_count)) + geom_col(aes(fill = party == "(Con)"))

# probably quite a bit of error given that numbers etc haven't been removed.
# would be interesting to look at who 'gives the most numbers' etc...
words_per_lord %<>% add_gender()
words_per_lord %<>% mutate(name =  as.factor(name))
words_per_lord %>% ggplot(aes(x = fct_reorder(name, word_count), y = word_count)) + geom_col(aes(fill = gender)) 

# ladies look evenly distributed among speech lengths
words_per_lord %>% group_by(gender) %>% summarise(total_words = sum(word_count), total_speakers = length(name)) %>% ungroup() %>%
  mutate(tot_s = sum(total_speakers), tot_w = sum(total_words), exp = tot_w*(total_speakers/tot_s))

appearances_tib %>% group_by(gender) %>% summarise(n_speeches = length(name), n_speakers = length(unique(name))) %>% ungroup() %>% 
  mutate(tot_s = sum(n_speeches), exp = tot_s * n_speakers/sum(n_speakers))

# how often did each party speak?

speeches_by_party <- appearances_tib %>% group_by(party) %>% summarise(n_speeches = n())

# how often would you expect each to speak based on number of lords present?

exp_speeches <- appearances_tib %>% distinct(name, party) %>% group_by(party) %>% summarise(n = n()) %>%
  mutate(total_speeches = 247, nprob = n/sum(n), expected_nspeeches = round(total_speeches*nprob)) 

speeches_by_party %>% left_join(exp_speeches) %>% select(party,n_speeches,expected_nspeeches) %>% 
  gather(speech_type, count, n_speeches, expected_nspeeches) %>%
  ggplot(aes(party, count)) + geom_col(aes(fill = speech_type), position = "dodge")

head_vs_hayt <- speech_tib %>% mutate(chars_used = str_length(all_speeches)) %>% arrange(desc(chars_used)) %>% top_n(2)
speech_tib %>% mutate(words_used = sum(str_detect(all_speeches, "[^ ]+"), na.rm = TRUE)) %>% select(words_used)

head_vs_hayt %>% 
  unnest_tokens(word, all_speeches) %>%
  anti_join(stop_words) %>% 
  group_by(name) %>%
  count(word) %>% arrange(desc(n)) %>% top_n(9) %>%
  ggplot(aes(word, n)) +
  geom_col() +
  coord_flip() +
  facet_wrap(~name)

hh_tidy <- head_vs_hayt %>% 
  unnest_tokens(word, all_speeches) %>%
  anti_join(stop_words) %>% 
  group_by(name) %>%
  count(word)

hh_tidy %>% acast(word ~ name, value.var = "n", fill = 0) %>%
  comparison.cloud(colors = c("gray20", "gray80"),
                 max.words = 100)

# What about the order of speeches ? ----


party_seq <- appearances_tib$party
party_seq <- party_seq[!is.na(party_seq)]
get_seq <- function(vec) {
  grp_cnt <- NULL
  count = 0
  i = 1
  while (i < length(vec)) {
    count  = 0
    j = i
    while (j < length(vec)) {
      if (is.na(vec[i]) | is.na(vec[j])) {
        break
      }
      if (vec[i] == vec[j]) {
        count = count + 1
      } else  if (count > 1) {
        i = i + count - 1
        break
      } else {
        break
      }
      j = j + 1
    }
    grp_cnt <- c(grp_cnt, count)
    i = i + 1
  }
  grp_cnt
}
party_seq_values <- get_seq(party_seq)
party_seq_index <- cumsum(party_seq_values)
party_seq_tib <- tibble(party = party_seq[party_seq_index], run = party_seq_values)
ggplot(party_seq_tib) +
  geom_col(aes(x = party, y = run))

party_seq_tib %<>% mutate(index = row_number())

ggplot(party_seq_tib) +
  geom_point(aes(index, run, colour = party))

ggplot(party_seq_tib) +
  geom_histogram(aes(run, fill = party))

l1 <- as.list(party_seq_tib$party)
l2 <- as.list(party_seq_tib$run)
x <- map2(l1, l2, rep) %>% unlist()
y <- map(l2, ~seq(1, .x)) %>% unlist()
tibble(x, y) %>% mutate(r = row_number()) %>%
  ggplot(aes(r, y)) +
  geom_point(aes(colour = x)) 
  
# What about the pairs of speakers ? ----

sequence_tib <- appearances_tib %>% select(-speeches)
sequence_tib %<>% mutate(name_shift = lead(name), party_shift = lead(party))

# Count number of pairs of speakers
sequence_tib %<>% group_by(name, name_shift) %>% summarise(weights = n()) %>% arrange(desc(weights)) %>% ungroup()

scanseq <- sequence_tib[1,] %>% mutate(temp = name, name = name_shift, name_shift = temp)
scanseqs <- list()

for (i in 1:dim(sequence_tib)[1]) {
  scanseqs[[i]] <- c(sequence_tib[i,2], sequence_tib[i,1])
}



shuffled <- sequence_tib %>% ungroup() %>% mutate(temp = name_shift, name_shift = name, name = temp) %>% select(-temp)
shuffled

sequence_tib %>% bind_rows(shuffled)

sequence_tib %>% select(name, name_shift) %>% group_by(name, name_shift) %>% summarise(n = n()) %>% spread(name, n) %>% View()

test <- list(c("a", "b"), c("b", "a"))
test[[1]] %in% test[[2]]

sequence_tib[1,]
test <- distinct(sequence_tib, name, name_shift)
test %>% semi_join(test, by = c("name_shift" = "name", "name" = "name_shift"))

nrows <- dim(sequence_tib)[1]
pairlist <- list()
for (i in 1:nrows) {
  pairlist[[i]] <- c(sequence_tib[i,1], sequence_tib[i,2])
}

duplicated(pairlist)

sequence_tib <- appearances_tib %>% select(-speeches)
sequence_tib %<>% mutate(name_shift = lead(name), party_shift = lead(party))
sequence_tib %<>% mutate(px = pmin(name, name_shift), py = pmax(name, name_shift))

paired_seq_tib <-  sequence_tib %>% 
  group_by(px, py) %>%
  summarise(weights = n()) %>% arrange(desc(weights), px)  %>% filter(!is.na(px))

total_weights <- paired_seq_tib %>% gather(temp, speaker, -weights) %>% select(-temp) %>% 
  group_by(speaker) %>% summarise(total_weight = sum(weights)) %>% arrange(desc(total_weight))

num_appearances <- appearances_tib %>% select(name) %>% group_by(name) %>% count() %>% arrange(desc(n))

# Normalise weights by how often a speaker spoke?

# paired seq tib is an edge list
library(network)
nodes <- appearances_tib %>% distinct(name) %>% select(name) 
routes_network <- network(paired_seq_tib, vertex.attr = nodes, matrix.type = "edgelist", ignore.eval = FALSE)
plot(routes_network, vertex.cex = 2, mode = "circle")

# try again but filter out speakers who made only one interaction
multi_pst <- paired_seq_tib %>% filter(weights > 1)
nodes_pst <- tibble(name = unique(c(multi_pst$px, multi_pst$py)))
routes_network <- network(multi_pst, vertex.attr = nodes, matrix.type = "edgelist", ignore.eval = FALSE)
plot(routes_network, vertex.cex = 2, mode = "circle")

# Same in igraph

detach(package:network)
rm(routes_network)
library(igraph)

routes_igraph <- graph_from_data_frame(d = multi_pst, vertices = nodes, directed = TRUE)
routes_igraph
plot(routes_igraph, edge.arrow.size = 0.2)
plot(routes_igraph, layout = layout_with_graphopt, edge.arrow.size = 0.2, size = 30)

library(tidygraph)
library(ggraph)

routes_tidy <- tbl_graph(nodes = nodes, edges = paired_seq_tib, directed = TRUE)
routes_igraph_tidy <- as_tbl_graph(routes_igraph)

routes_igraph_tidy
routes_tidy
ggraph(routes_tidy) + geom_edge_link() + geom_node_point() + theme_graph()

ggraph(routes_tidy, layout = "graphopt") + 
  geom_node_point() +
  geom_edge_link(aes(width = weights), alpha = 0.8) + 
  scale_edge_width(range = c(0.2, 2)) +
  labs(edge_width = "Interactions") +
  theme_graph()

routes_tidy <- tbl_graph(nodes = nodes, edges = paired_seq_tib, directed = TRUE)
routes_igraph_tidy <- as_tbl_graph(routes_igraph)
ggraph(routes_tidy) + geom_edge_link() + geom_node_point() + theme_graph()



# What can we say about a single speaker? ----

headley_all <- full_speeches %>% filter(name == "Lord Bridges of Headley")

headley <- appearances_tib %>% filter(name == "Lord Bridges of Headley")

hwords <- headley_all$all_speeches 

str_extract(hwords, "\\b.+\\b")
str_extract_all(hwords, "[ ][^ ]*[ ]") %>% head(100)

# most used words
headley_words <- unnest_tokens(headley_all, word, all_speeches) %>% 
  select(-c(name,party, gender))

headley_words %>% group_by(word) %>% summarise(n = n()) %>% arrange(desc(n)) %>% View()

headley_words %>% anti_join(stop_words) %>% group_by(word) %>% summarise(n = n()) %>% arrange(desc(n)) %>% View()

# Most used phrases

headley_bigrams <- unnest_tokens(headley_all, bigram, all_speeches, token = "ngrams", n = 2) %>% 
  select(-c(name,party, gender))

headley_bigrams %>% group_by(bigram) %>% summarise(n = n()) %>% arrange(desc(n)) %>% View()

# get meaningful bigrams (those not where both words are stop words)
stop_words %<>% filter(!str_detect(word, "^.$"))
s_words <- str_c(stop_words$word, collapse = "|")

headley_bigrams %>% group_by(bigram) %>% mutate(sw = str_detect(bigram, str_c("(", s_words, ")", " ", "(", s_words, ")(?!.)"))) %>% 
  filter(!sw) %>% group_by(bigram) %>% summarise(n = n()) %>% arrange(desc(n)) %>% View()

# headley context search, automatically reduced to lower case by tidy text. 

# hwords %>% str_extract_all("[ ][:alnum:]*[ |\\.]")
hwords_collapsed <- str_c(headley_words$word, collapse = " ")
hwords_collapsed %>% str_match_all(".eu [:alnum:]* [:alnum:]*")

regex_patterns <- list()
rgx_nms <- c("eu", "uk", "parliament", "government")
regex_patterns <- str_c(c(".eu", "uk", ".parliament", ".government"),
                        " [:alnum:]* [:alnum:]*")

regex_patterns %<>% set_names(rgx_nms)
regex_patterns

hwords_collapsed %>% str_match_all(regex_patterns[[4]])

# Apply to all lords ----

words_total <- unnest_tokens(speech_tib, word, all_speeches) 
words_total

# sentiment analysis

afinn <- get_sentiments("afinn")
afinn

words_total %>% 
  inner_join(afinn) %>%
  group_by(name) %>% 
  filter(!str_detect(word, "noble|Noble|lord|Lords|Lord")) %>%
  summarise(s = sum(score), n = length(word)) %>%
  arrange(s) %>%
  ggplot(aes(name, s/sqrt(n))) +
  geom_point(aes(size = n)) +
  coord_flip()

# topic modelling

library(tm)
library(topicmodels)

dtm <- appearances_tib %>% 
  mutate(r = row_number()) %>% 
  unnest_tokens(word, speeches) %>% 
  group_by(name, r, word) %>% 
  summarise(count = length(word)) %>%
  arrange(r)

dtm %<>% ungroup() %>% anti_join(stop_words)

dtm %<>% filter(word %!in% my_stop_words)

dtm %<>% group_by(r) %>% mutate(n_words = sum(count)) 
docLength <- dtm %>% distinct(r, n_words)
hist(docLength$n_words, breaks = 100)
dtm %<>% filter(n_words < 50) # do this before removing stop words
full_speeches$all_speeches %>% str_extract_all("Amendment.........")

# Number of amendments 36,21,43,17,20,18,19,34,16,33,44,39,11,29,9B,40,25,31,38,35,12,13,10
n_amendments <- c(36,21,43,17,20,18,19,34,16,33,44,39,11,29,9,40,25,31,38,35,12,13,10)

dtm_obj <- cast_dtm(dtm, r, word, count)

dtm_obj

hansard_lda <- LDA(dtm_obj, k = 5, control = list(seed = 1234))

hansard_lda

h_topics <- tidy(hansard_lda, matrix = "beta")

hansard_top_terms <- h_topics %>%
  group_by(topic) %>%
  top_n(10, beta) %>%
  ungroup() %>%
  arrange(topic, -beta)

hansard_top_terms %>%
  mutate(term = reorder(term, beta)) %>%
  ggplot(aes(term, beta, fill = factor(topic))) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ topic, scales = "free") +
  coord_flip()

beta_spread <- h_topics %>%
  mutate(topic = paste0("topic", topic)) %>%
  spread(topic, beta) %>%
  filter(topic1 > 0.001 | topic2 > 0.001) %>%
  mutate(log_ratio = log2(topic2 / topic1))

beta_spread

# Topic modelling using LDA feel like too much of a black box.

# New approach:

tidy_dtm <- appearances_tib %>% 
  mutate(r = row_number()) %>% 
  unnest_tokens(word, speeches) %>% 
  group_by(name, r, word) %>% 
  summarise(count = length(word)) %>%
  arrange(r)

tidy_dtm %<>% group_by(r) %>% mutate(n_words = sum(count))

tidy_dtm %>% distinct(n_words)

appearances_tib$speeches[[4]] # 200 words seems like the lower limit for an informative document

tidy_dtm %<>% filter(n_words > 200)

tidy_dtm %<>% anti_join(stop_words)

my_stop_words <- c("lord", "noble", "friend", "lords", "house", "minister", "1", "lordships")

tidy_dtm %<>% filter(word %!in% my_stop_words)

tidy_dtm %<>% filter(count > 1)

tidy_dtm %<>% group_by(r, word) %>% mutate(doc_word_frequency = count/n_words, norm_dwf = (doc_word_frequency - min(doc_word_frequency)) - (max(doc_word_frequency) - min(doc_word_frequency))) %>%
  ungroup() %>% mutate(total_words = sum(count)) %>% group_by(word) %>% mutate(corpus_word_freq = sum(count)/total_words) 

tidy_dtm %>% distinct(word, corpus_word_freq) %>% arrange(desc(corpus_word_freq)) %>% View()

top_dtm <- tidy_dtm %>% arrange(r, desc(doc_word_frequency)) %>% group_by(r) %>% top_n(10, doc_word_frequency) %>% mutate(wordsInSpeech = length(word))
top_dtm %<>% group_by(r, doc_word_frequency) %>% mutate(nrepeats = n(), tooMany = ifelse(nrepeats > wordsInSpeech/3 & count < 3, TRUE, FALSE)) %>% filter(!tooMany)

top_words <- top_dtm %>% split(.$r) %>% map("word")

not_shared <- list()
for (i in seq_along(top_words)) {
  if(i != 1) {
    not_shared[[i]] <-  top_words[[i]][top_words[[i]] %!in% top_words[[i-1]]]
  }
  if(i == 1){
    not_shared[[i]] <- top_words[[i]]
  }
}

shared <- list()
for (i in seq_along(top_words)) {
  if(i != 1) {
    shared[[i]] <-  top_words[[i]][top_words[[i]] %in% top_words[[i-1]]]
  }
  if(i == 1){
    shared[[i]] <- top_words[[i]]
  }
}


not_shared
shared


tidy_dtm$doc_word_frequency %>% sort() %>% as.tibble() %>% mutate(r = row_number(), l = length(r), p = r/l) %>%
  ggplot(aes(value, p)) + geom_line()


# counting even more things ----

# Number of questions

full_speeches %>% group_by(name) %>% mutate(numQs = str_count(all_speeches, "\\?")) %>% View()

s <- full_speeches %>% filter(name == "Lord Oates") %>% pull(all_speeches)
qwords <- "(\\Wdo|\\Wwhat|\\Wwhere|\\Wwho|\\Wwhy|\\Wwhen|\\Whow|\\Wif|\\Whas|\\Wwill|\\?)"
str_extract_all(s, "\\w+\\?")
str_extract_all(s, "\\?")
initial_matches <- str_extract_all(s, qwords)[[1]]
initial_match_indexes_start <- which(initial_matches == "?") - 1
initial_match_indexes_end <- which(initial_matches == "?")
qword_positions <- str_locate_all(s, qwords)[[1]]
str_sub(s, qword_positions[initial_match_indexes_start], qword_positions[initial_match_indexes_end])

# Pull questions
pull_questions <- function(string) {
  # pull the questions asked in a string, and the question word used.
  qwords <- "(\\Wdo|\\Wwhat|\\Wwhere|\\Wwho|\\Wwhy|\\Wwhen|\\Whow|\\Wif|\\Whas|\\Wwill|\\Wdoes|\\?)"
  initial_matches <- str_extract_all(string, qwords)[[1]]
  initial_match_indexes_start <- which(initial_matches == "?") - 1
  initial_match_indexes_end <- which(initial_matches == "?")
  qword_positions <- str_locate_all(string, qwords)[[1]]
  question_sentence <- str_sub(string, qword_positions[initial_match_indexes_start], qword_positions[initial_match_indexes_end])
  question_word <- initial_matches[initial_match_indexes_start]
  
  sentence_matches <- str_extract_all(string, "\\.|\\:|\\?")[[1]]
  sentence_matches_start <- which(sentence_matches == "?") - 1
  sentence_matches_end <- which(sentence_matches == "?")
  qsentence_positions <- str_locate_all(string, "\\.|\\:|\\?")[[1]]
  question_sentence_full <- str_sub(string, qsentence_positions[sentence_matches_start], qsentence_positions[sentence_matches_end])
  
  return(tibble(question_word, question_sentence, question_sentence_full))
}

pull_questions(s) %>% View()
# Number of unique words used

total_words <- unique(tidy_dtm$word)
tidy_dtm %>% group_by(word) %>% mutate(total_count = n()) %>%
  group_by(name) %>% summarise(total_words = sum(count), num_unique = sum(total_count == count), prop_unique = num_unique/total_words) %>%
  arrange(desc(prop_unique))

# Number of times other lords are mentioned

surname <- full_speeches$name %>% str_match("^(?:\\w+\\s)(\\w+)") 
surname <- surname[,2] %>% str_to_lower()
for (i in seq_along(surname)) {
  surname[i] <- str_c("\\s", surname[i], "\\W")
}

surname <- surname[which(surname != '\\sO\\W' & surname != '\\sDe\\W')]
pronouns <- c('his lordship', 'the baroness', 'the lord', 'the minister', 'her ladyship', 'the noble lords?(?!(.{0,4}lord))', 'reverend primate')
named_references <- c(surname, pronouns) 
named_references_reg <- str_c("(", str_c(named_references, collapse = "|"), ")")

# Problems: Some names match other words e.g. 'true', 'hunt'. double barrelled names. 
# instances where someone refers to 'the noble lord, lord blencathra' will be counted twice
# could solve this using negative lookahead on 'the noble'
appearances_tib %<>% mutate(speeches = str_to_lower(speeches)) %>% filter(!is.na(speeches))

appearances_tib %>% group_by(name) %>% mutate(n_references = str_count(speeches, named_references_reg)) %>% View()

s <- appearances_tib %>% filter(name == 'Lord Winston') %>% pull(speeches) 
s <- appearances_tib$speeches[[1]] 
s <- "The noble Lord, Lord Howard, and his noble steed carrying him, are followed by Lord Chubbington and his noble donkey, Assworth. There was supposedly a third lord, but the noble Lord being too drunk, did not arrive for the adventure."
str_view_all(s, named_references_reg)
str_extract_all(s, named_references_reg)
str_view_all(s, "noble Lords?(?!(.{0,2}Lord))")
# want to find number of qs per x many words

# word associations

assoc_pattern <- function(word) {str_c("\\.[^.]+\\W", word, "(\\.|\\W[^.]+?(?=\\.))")}
str_extract_all(s, assoc_pattern("leave"))

eu_docs <- map(appearances_tib$speeches, str_extract_all, assoc_pattern("eu"))
head(eu_docs)
eu_docs %<>% flatten() %>% flatten() 

tibble(doc = unlist(eu_docs)) %>% mutate(r = row_number()) %>% group_by(r) %>% unnest_tokens(word, doc) %>% 
  anti_join(stop_words) %>% group_by(word) %>% summarise(count = n()) %>% arrange(desc(count)) %>% View()