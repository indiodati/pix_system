module ApplicationHelper
	def withdrawal_status_badge_classes(status)
	  base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold ring-1"

	  case status.to_s.downcase
	  when "paid", "pago"
	    "#{base} bg-emerald-50 text-emerald-700 ring-emerald-100"
	  when "failed", "falhou"
	    "#{base} bg-rose-50 text-rose-700 ring-rose-100"
	  else # pending / pendente
	    "#{base} bg-amber-50 text-amber-700 ring-amber-100"
	  end
	end

end
