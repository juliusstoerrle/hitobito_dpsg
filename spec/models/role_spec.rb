# frozen_string_literal: true

#  Copyright (c) 2026, Deutsche Pfadfinder*innenschaft Sankt Georg. This file is part of
#  hitobito_dpsg and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_dpsg

require "spec_helper"

describe Role do
  describe "exclusive membership roles (hitobito/hitobito_dpsg#26)" do
    let(:person) { Fabricate(:person) }
    let(:adler_mitglieder) { groups(:adler_mitglieder) } # layer: adler
    let(:biber_mitglieder) { groups(:biber_mitglieder) } # layer: biber

    let!(:ordentliche_in_adler) do
      Group::Mitglieder::OrdentlicheMitgliedschaft.create!(
        person: person, group: adler_mitglieder
      )
    end

    def create_ordentliche_in_biber
      Group::Mitglieder::OrdentlicheMitgliedschaft.create!(person: person, group: biber_mitglieder)
    end

    describe "global exclusivity of Ordentliche- and Foerdermitgliedschaft" do
      it "rejects a second OrdentlicheMitgliedschaft in the same Stamm" do
        role = Group::Mitglieder::OrdentlicheMitgliedschaft
          .new(person: person, group: adler_mitglieder)

        expect(role).not_to be_valid
        expect(role.errors[:base].first).to include("Ordentliche")
      end

      it "rejects a second OrdentlicheMitgliedschaft in another Stamm" do
        role = Group::Mitglieder::OrdentlicheMitgliedschaft
          .new(person: person, group: biber_mitglieder)

        expect(role).not_to be_valid
        expect(role.errors[:base].first).to include("Ordentliche")
      end

      it "rejects a Foerdermitgliedschaft in the same Stamm" do
        role = Group::Mitglieder::Foerdermitgliedschaft
          .new(person: person, group: adler_mitglieder)

        expect(role).not_to be_valid
        expect(role.errors[:base].first).to include("Ordentliche")
      end

      it "rejects a Foerdermitgliedschaft in another Stamm" do
        role = Group::Mitglieder::Foerdermitgliedschaft
          .new(person: person, group: biber_mitglieder)

        expect(role).not_to be_valid
      end
    end

    describe "exclusivity within a Stamm" do
      it "rejects a Zweitmitgliedschaft in the same Stamm" do
        role = Group::Mitglieder::Zweitmitgliedschaft
          .new(person: person, group: adler_mitglieder)

        expect(role).not_to be_valid
      end
    end

    describe "allowed combinations" do
      it "accepts a Zweitmitgliedschaft in another Stamm" do
        role = Group::Mitglieder::Zweitmitgliedschaft
          .new(person: person, group: biber_mitglieder)

        expect(role).to be_valid
      end

      it "accepts the same membership for another person" do
        role = Group::Mitglieder::OrdentlicheMitgliedschaft
          .new(person: people(:leader), group: adler_mitglieder)

        expect(role).to be_valid
      end

      it "accepts a membership after the previous one ended" do
        ordentliche_in_adler.update_columns(end_on: 1.month.ago.to_date)
        create_ordentliche_in_biber

        role = Group::Mitglieder::Zweitmitgliedschaft
          .new(person: person, group: adler_mitglieder)

        expect(role).to be_valid
      end
    end

    describe "validate_past: false behaviour" do
      it "accepts a mutation entirely in the past" do
        role = Group::Mitglieder::Zweitmitgliedschaft.new(
          person: person, group: adler_mitglieder,
          start_on: 6.months.ago.to_date, end_on: 4.months.ago.to_date
        )

        expect(role).to be_valid
      end

      it "accepts a backdated start_on overlapping an ended membership" do
        ordentliche_in_adler.update_columns(end_on: Date.yesterday)
        create_ordentliche_in_biber

        role = Group::Mitglieder::Zweitmitgliedschaft.new(
          person: person, group: adler_mitglieder,
          start_on: 2.months.ago.to_date
        )

        expect(role).to be_valid
      end

      it "still rejects an overlap in the current period" do
        role = Group::Mitglieder::Zweitmitgliedschaft.new(
          person: person, group: adler_mitglieder,
          start_on: 6.months.ago.to_date
        )

        expect(role).not_to be_valid
      end
    end
  end

  describe "prerequisite membership roles (hitobito/hitobito_dpsg#27)" do
    let(:person) { Fabricate(:person) }
    let(:adler_mitglieder) { groups(:adler_mitglieder) } # layer: adler
    let(:biber_mitglieder) { groups(:biber_mitglieder) } # layer: biber
    let(:adler_pfadfinder) { groups(:adler_pfadfinder) } # layer: adler

    def build_pfadfinder
      Group::StammGruppePfadfinder::Mitglied.new(person:, group: adler_pfadfinder)
    end

    it "has consistent fixtures" do
      expect(roles(:member)).to be_valid
    end

    it "requires a membership in the same Stamm for a Pfadfinder*in" do
      Group::Mitglieder::OrdentlicheMitgliedschaft.create!(person:, group: biber_mitglieder)

      role = build_pfadfinder

      expect(role).not_to be_valid
      expect(role.errors[:base]).to eq [
        "Für diese Rolle wird eine Ordentliche Mitgliedschaft, Fördermitgliedschaft oder " \
        "Zweitmitgliedschaft in Stamm Adler vorausgesetzt. Diese fehlt ab #{I18n.l(Date.current)}."
      ]
    end

    it "accepts a Zweitmitgliedschaft as membership for a Pfadfinder*in" do
      Group::Mitglieder::OrdentlicheMitgliedschaft.create!(person:, group: biber_mitglieder)
      Group::Mitglieder::Zweitmitgliedschaft.create!(person:, group: adler_mitglieder)

      expect(build_pfadfinder).to be_valid
    end

    it "requires an Ordentliche- or Foerdermitgliedschaft for a Zweitmitgliedschaft" do
      role = Group::Mitglieder::Zweitmitgliedschaft.new(person:, group: adler_mitglieder)

      expect(role).not_to be_valid
      expect(role.errors[:base]).to eq [
        "Für diese Rolle wird eine Ordentliche Mitgliedschaft oder Fördermitgliedschaft " \
        "vorausgesetzt. Diese fehlt ab #{I18n.l(Date.current)}."
      ]
    end

    context "with a Zweitmitgliedschaft" do
      let!(:ordentliche) do
        Group::Mitglieder::OrdentlicheMitgliedschaft.create!(person:, group: biber_mitglieder,
          start_on: 1.year.ago.to_date)
      end
      let!(:zweitmitgliedschaft) do
        Group::Mitglieder::Zweitmitgliedschaft.create!(person:, group: adler_mitglieder,
          start_on: 1.year.ago.to_date)
      end
      let!(:pfadfinder) do
        build_pfadfinder.tap { |role| role.update!(start_on: 1.year.ago.to_date) }
      end

      it "shortens the Zweitmitgliedschaft and its Pfadfinder*in when the membership ends" do
        ordentliche.update!(end_on: 1.month.from_now.to_date)

        expect(zweitmitgliedschaft.reload.end_on).to eq(1.month.from_now.to_date)
        expect(pfadfinder.reload.end_on).to eq(1.month.from_now.to_date)
      end

      it "ends the Zweitmitgliedschaft and its Pfadfinder*in when the membership is deleted" do
        ordentliche.destroy

        expect(zweitmitgliedschaft.reload.end_on).to eq(Date.yesterday)
        expect(pfadfinder.reload.end_on).to eq(Date.yesterday)
      end

      it "keeps the Pfadfinder*in when the Zweitmitgliedschaft is replaced by an Ordentliche" do
        PfadiDe::Role::PrerequisiteCascade.deferred do
          ordentliche.update!(end_on: Date.yesterday)
          zweitmitgliedschaft.update!(end_on: Date.yesterday)
          Group::Mitglieder::OrdentlicheMitgliedschaft.create!(person:, group: adler_mitglieder)
        end

        expect(pfadfinder.reload.end_on).to be_nil
      end
    end

    it "keeps dependent roles when the fee kind of the membership changes" do
      membership = roles(:member_ordentliche_mitgliedschaft)
      Role::FeeKindChange.new(membership,
        fee_kind_id: fee_kinds(:reduced_fee_kind).id,
        start_on: 1.month.from_now.to_date).save!

      expect(roles(:member).reload.end_on).to be_nil
    end
  end
end
