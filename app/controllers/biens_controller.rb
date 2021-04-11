class BiensController < ApplicationController
  CURRENT_YEAR = 2021
  CURRENT_START_PERIOD = Date.new(CURRENT_YEAR)
  CURRENT_END_PERIOD = Date.new(CURRENT_YEAR + 1) - 1.day

  before_action :set_biens, :any_loyer_missing_all_bien?, only: %i[index total_cash_flow]
  before_action :set_bien, :set_report, :any_loyer_missing_this_bien?, only: %i[show update]

  def index
    @markers = create_map_markers(@biens)
    # @sum_depenses = current_user.sum_depenses_biens
    puts "hey you"

    @cfbiens = @biens.map(&:cash_flow_bien_to_date)
    @cfbiens_months = current_user.cash_flow_biens.reverse

    cash_flow_courbe_biens

    @months_display = (0..11).map { |i| (Date.today - i.month).end_of_month.strftime('%b %y') }.reverse
    @apartments_display = current_user.biens.map { |bien| bien.nom }

    @apartments_id = current_user.biens.map { |bien| bien.id }

    # KPIS
    @total_cash_flow = total_cash_flow
    @rentability_ytd_all_biens = rentability_ytd_all_biens
  end

  def show
    ## MERGE tableaux transactions ##
    @lasts_transactions = (@bien.loyers.where('date_paiement < ?',
                                              DateTime.now).order(date_paiement: :desc).limit(10).to_a + @bien.depenses.where('date_paiement < ?',
                                                                                                                              DateTime.now).order(date_paiement: :desc).limit(10).to_a).map(&:attributes)
    @lasts_transactions.sort_by! { |t| t['date_paiement'] }.reverse!
    @depenses = @bien.sum_depenses

    @cash_flow_bien_month = @bien.cash_flow_month.reverse

    @months_display = (0..11).map { |i| (Date.today - i.month).end_of_month.strftime('%b %y') }.reverse

    @cash_flow_courbe_bien = @cash_flow_bien_month.each_with_index.map do |n, index|
      if index.zero?
        n
      else
        @cash_flow_bien_month[0..index].sum
      end
    end
  end

  def update
    @bien.attributes = bien_params

    if @bien.save
      redirect_to bien_path(@bien), success: "🛒 Dépense ajoutée !"
    else
      render :show
    end
  end

  def new
    @bien = Bien.new
  end

  def create
    @bien = Bien.new(bien_params)
    @bien.user = current_user

    if @bien.save
      redirect_to bien_path(@bien)
    else
      render :new
    end
  end

  private

  def create_map_markers(biens)
    biens.map do |bien|
      bien.categorie == "Maison" ? @image_url = helpers.asset_url('house-user-solid.svg') : @image_url = helpers.asset_url('building-solid.svg')
      {
        lat: bien.latitude,
        lng: bien.longitude,
        infoWindow: render_to_string(partial: "info_window", locals: { bien: bien }),
        image_url: @image_url
      }
    end
  end

  def bien_params
    params
      .require(:bien)
      .permit(
        :nom,
        :categorie,
        :adresse,
        :ville,
        :code_postal,
        :pays,
        :info_compl_adresse,
        :surface,
        :nb_pieces,
        :nb_sdb,
        :nb_etages,
        :num_etage,
        :annee_construction,
        :prix_acquisition,
        :date_acquisition,
        :frais_achat_notaire,
        :frais_achat_agence,
        :frais_achat_travaux,
        :frais_achat_autres,
        :montant_loyer,
        depenses_attributes: %i[
          id
          nom
          montant
          categorie
          date_paiement
        ]
      )
  end

  def months_display_12
    @months_display = (0..11).map { |i| (Date.today - i.month).end_of_month.strftime('%b') }
  end

  def sum_cashflow_courbe
    b = @cfbiens_months.each with_index.map do |n, index|
      if index.zero?
        n
      else tab[0..index].sum
      end
    end
  end

  def set_bien
    @bien = Bien.find(params[:id])
  end

  def set_biens
    @biens = current_user.biens.includes(:loyers)
  end

  def set_report
    ############################ Generate the loyers paid & to be paid ###########################################
    loyers_received_list = @bien.loyers.in_interval(CURRENT_START_PERIOD, Date.today)
    @loyers_received = loyers_received_list.reduce(0) { |sum, loyer| sum + loyer }

    # Simulate future loyers
    nb_loyers_tbr = 12 - loyers_received_list.count
    @loyers_tbr = nb_loyers_tbr * @bien.montant_loyer

    ############################ Generate the depenses paid & to be paid ###########################################
    # CREDIT
    credits_paid_list = @bien.depenses.cat_credit.in_interval(CURRENT_START_PERIOD, Date.today)
    @credits_paid = credits_paid_list.reduce(0) { |sum, credit| sum + credit }

    credits_tbp_list = @bien.depenses.cat_credit.in_interval(Date.today, CURRENT_END_PERIOD)
    @credits_tbp = credits_tbp_list.reduce(0) { |sum, credit| sum + credit }

    # TAXE FONCIERE
    taxe_fonciere_paid_list = @bien.depenses.cat_taxe_fonciere.in_interval(CURRENT_START_PERIOD, Date.today)
    @taxe_fonciere_paid = taxe_fonciere_paid_list.reduce(0) { |sum, taxe_fonciere| sum + taxe_fonciere }

    taxe_fonciere_tbp_list = @bien.depenses.cat_taxe_fonciere.in_interval(Date.today, CURRENT_END_PERIOD)
    @taxe_fonciere_tbp = taxe_fonciere_tbp_list.reduce(0) { |sum, taxe_fonciere| sum + taxe_fonciere }

    # COPROPRIETE
    copropriete_paid_list = @bien.depenses.cat_copropriete.in_interval(CURRENT_START_PERIOD, Date.today)
    @copropriete_paid = copropriete_paid_list.reduce(0) { |sum, copropriete| sum + copropriete }

    copropriete_tbp_list = @bien.depenses.cat_copropriete.in_interval(Date.today, CURRENT_END_PERIOD)
    @copropriete_tbp = copropriete_tbp_list.reduce(0) { |sum, copropriete| sum + copropriete }

    # ASSURANCES
    assurances_paid_list = @bien.depenses.cat_assurances.in_interval(CURRENT_START_PERIOD, Date.today)
    @assurances_paid = assurances_paid_list.reduce(0) { |sum, assurance| sum + assurance }

    assurances_tbp_list = @bien.depenses.cat_assurances.in_interval(Date.today, CURRENT_END_PERIOD)
    @assurances_tbp = assurances_tbp_list.reduce(0) { |sum, assurance| sum + assurance }

    # TRAVAUX
    travaux_paid_list = @bien.depenses.cat_travaux.in_interval(CURRENT_START_PERIOD, Date.today)
    @travaux_paid = travaux_paid_list.reduce(0) { |sum, travaux| sum + travaux }

    travaux_tbp_list = @bien.depenses.cat_travaux.in_interval(Date.today, CURRENT_END_PERIOD)
    @travaux_tbp = travaux_tbp_list.reduce(0) { |sum, travaux| sum + travaux }

    # AUTRES
    autres_paid_list = @bien.depenses.cat_autres.in_interval(CURRENT_START_PERIOD, Date.today)
    @autres_paid = autres_paid_list.reduce(0) { |sum, autres| sum + autres }

    autres_tbp_list = @bien.depenses.cat_autres.in_interval(Date.today, CURRENT_END_PERIOD)
    @autres_tbp = autres_tbp_list.reduce(0) { |sum, autres| sum + autres }

    ############################ Generate the total for suivi fin ###########################################
    @total_paid = @loyers_received - (@credits_paid + @taxe_fonciere_paid + @copropriete_paid + @assurances_paid + @travaux_paid + @autres_paid)
    @total_tbp = @loyers_tbr - (@credits_tbp + @taxe_fonciere_tbp + @copropriete_tbp + @assurances_tbp + @travaux_tbp + @autres_tbp)
  end

  def any_loyer_missing_all_bien?
    @any_loyer_missing_all_bien = @biens.any? do |bien|
      bien.loyers.empty? || bien.loyers.last.date_paiement.month != Date.today.month
    end
  end

  def any_loyer_missing_this_bien?
    @any_loyer_missing_this_bien = @bien.loyers.empty? || @bien.loyers.last.date_paiement.month != Date.today.month
  end

  def cash_flow_courbe_biens
    @cash_flow_courbe_biens = @cfbiens_months.each_with_index.map do |n, index|
      if index.zero?
        n
      else
        @cfbiens_months[0..index].sum
      end
    end
  end

  def total_cash_flow
    @biens.map { |bien| bien.cash_flow_bien_to_date }.sum
  end

  def rentability_ytd_all_biens
    sum_loyers_ytd_all_biens = @biens.reduce(0) do |sum_loyers, bien|
      sum_loyers + bien.months_loyers.sum
    end

    sum_depenses_ytd_all_biens = @biens.reduce(0) do |sum_depenses, bien|
      sum_depenses + bien.months_depenses.sum
    end

    sum_loyers_depenses_ytd_all_biens = sum_loyers_ytd_all_biens - sum_depenses_ytd_all_biens

    prix_acquisition_all_biens = @biens.reduce(0) { |sum, bien| sum + bien.prix_acquisition }

    (sum_loyers_depenses_ytd_all_biens / prix_acquisition_all_biens.to_f) * 100
  end
end
