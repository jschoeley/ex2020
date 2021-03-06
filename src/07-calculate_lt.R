# Calculate life tables

# Init ------------------------------------------------------------

library(here); library(glue)
library(tidyverse)
library(patchwork)

# Constants -------------------------------------------------------

wd <- here()
cnst <- list()
cnst <- within(cnst, {
  regions_for_analysis = c(
    'AT', 'BE', 'BG', 'CH', 'CL', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR',
    'GB-EAW', 'GB-NIR', 'GB-SCT',
    'HU', 'IL', 'LT', 'NL', 'PL', 'PT', 'SE', 'SI'
  )
  out_path = glue('{wd}/out')
})

dat <- list()
fig <- list()

# Data ------------------------------------------------------------

dat$lt_input <- readRDS(glue('{wd}/out/lt_input.rds'))

dat$lt_input_sub <-
  dat$lt_input %>%
  filter(region_iso %in% cnst$regions_for_analysis)

# Function --------------------------------------------------------

source(glue('{wd}/cfg/fig_specs.R'))

# simple piecewise-exponential life-table
CalculateLifeTable <- 
  function (df, x, nx, Dx, Ex) {
    
    require(dplyr)
    
    df %>%
    transmute(
      x = {{x}},
      nx = {{nx}},
      mx = {{Dx}}/{{Ex}},
      px = exp(-mx*{{nx}}),
      qx = 1-px,
      lx = head(cumprod(c(1, px)), -1),
      dx = c(-diff(lx), tail(lx, 1)),
      Lx = dx/mx,
      Tx = rev(cumsum(rev(Lx))),
      ex = Tx/lx
    )  
    
  }

# Life table calculations -----------------------------------------

# life-tables by year
dat$lt <-
  dat$lt_input_sub %>%
  arrange(region_iso, sex, year, age_start) %>%
  group_by(region_iso, sex, year) %>%
  group_modify(~{
    CalculateLifeTable(.x, age_start, age_width, death, population_midyear)
  }) %>%
  ungroup()

# average yearly change in ex 2015 to 2019
dat$lt_annual_change_pre2020 <-
  dat$lt %>%
  filter(year %in% 2015:2019) %>%
  group_by(region_iso, sex, x) %>%
  summarise(
    # arithmetic mean of ex annual change
    avg_annual_diff_years = mean(diff(ex), na.rm = TRUE),
    # geometric mean of ex relative annual growth
    avg_annual_diff_pct = prod(ex[-1]/head(ex, -1))^(1/(n()-1))
  ) %>%
  ungroup()

# yearly change in ex 2020 to 2019
dat$lt_annual_change_2020 <-
  dat$lt %>%
  filter(year %in% c(2019, 2020)) %>%
  group_by(region_iso, sex, x) %>%
  summarise(
    # arithmetic mean of ex annual change
    avg_annual_diff_years = mean(diff(ex)),
    # geometric mean of ex relative annual growth
    avg_annual_diff_pct = prod(ex[-1]/head(ex, -1))^(1/(n()-1))
  ) %>%
  ungroup()

dat$lt_annual_change <- 
  full_join(
    dat$lt_annual_change_pre2020,
    dat$lt_annual_change_2020,
    by  = c('region_iso', 'sex', 'x'),
    suffix = c('pre2020', '2020')
  )

# age-specific contributions to differences in e0 2020 - 2019
dat$lt_20192020 <-
  dat$lt %>%
  filter(year %in% c(2019, 2020)) %>%
  select(region_iso, sex, year, x, lx, Lx, Tx, ex) %>%
  pivot_wider(names_from = year, values_from = c(ex, lx, Lx, Tx, ex)) %>%
  mutate(
    ex_diff = ex_2020 - ex_2019
  )

# Changes in remaining life-expectancy ----------------------------

map(c(0, 60, 80), ~{
  fig[[glue('age{.x}')]] <<-
    dat$lt_20192020 %>%
    filter(x == .x) %>%
    mutate(
      x = as.factor(x),
      region_iso = fct_reorder(region_iso, -ex_diff)
    ) %>%
    ggplot(aes(x = region_iso, color = sex, fill = sex, group = sex)) +
    geom_col(
      aes(y = ex_diff),
      position = position_dodge(width = 0.6), width = 0.4
    ) +
    geom_point(
      aes(x = region_iso, color = sex, y = avg_annual_diff_years),
      position = position_dodge(width = 0.6), width = 0.4,
      data = dat$lt_annual_change_pre2020 %>% filter(x == .x)
    ) +
    geom_hline(yintercept = 0) +
    coord_flip(ylim = c(-2, 1)) +
    #guides(color = 'none', fill = 'none') +
    scale_color_manual(values = fig_spec$sex_colors) +
    scale_fill_manual(values = fig_spec$sex_colors) +
    guides(
      color = guide_legend(reverse = TRUE),
      fill = guide_legend(reverse = TRUE)
    ) +
    labs(
      subtitle = glue('at age {.x}'),
      y = NULL,
      x = NULL
    ) +
    fig_spec$MyGGplotTheme(grid = 'xy', scaler = 0.8) +
    theme(legend.title = element_blank())
})

fig$ex_annual_change <-
  fig$age0 + fig$age60 + fig$age80 +
  plot_layout(guides = 'collect') +
  plot_annotation(
    title = 'Annual change in years of remaining life-expectancy 2019 to 2020',
    subtitle = 'Points mark the average annual change in life-expectancy 2015 to 2019'
  )
fig$ex_annual_change
fig_spec$ExportFigure(fig$ex_annual_change, path = cnst$out_path)
